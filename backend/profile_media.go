package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	_ "image/png"
	"math"
	"os"
	"path/filepath"
	"strings"

	"github.com/gofiber/fiber/v3"
)

const profileUploadLimit = 8 << 20

type profileMedia struct {
	Avatar   string   `json:"avatar"`
	Gallery  []string `json:"gallery"`
	Revision int64    `json:"revision"`
}
type profileMediaStore interface {
	ReadProfileMedia(string) (profileMedia, error)
	WriteProfileMedia(string, int64, profileMedia) (bool, error)
}

func (s *graphStore) ReadProfileMedia(owner string) (profileMedia, error) {
	rows, err := s.query(`MATCH(u:User {id:$id}) RETURN coalesce(u.profile_media,'')`, map[string]interface{}{"id": owner})
	if err != nil {
		return profileMedia{}, err
	}
	if !rows.Next() {
		return profileMedia{}, errNotFound
	}
	value, _ := rows.Record().GetByIndex(0)
	out := profileMedia{Gallery: []string{}}
	if raw, ok := value.(string); ok && raw != "" {
		err = json.Unmarshal([]byte(raw), &out)
	}
	return out, err
}
func (s *graphStore) WriteProfileMedia(owner string, revision int64, value profileMedia) (bool, error) {
	value.Revision = revision + 1
	raw, err := json.Marshal(value)
	if err != nil {
		return false, err
	}
	rows, err := s.query(`MATCH(u:User {id:$id}) WHERE coalesce(u.media_revision,0)=$revision SET u.media_revision=$next,u.profile_media=$data RETURN u.id`, map[string]interface{}{"id": owner, "revision": revision, "next": value.Revision, "data": string(raw)})
	if err != nil {
		return false, err
	}
	return rows.Next(), nil
}
func mediaView(owner string, p profileMedia) fiber.Map {
	photo := func(key string) any {
		if key == "" {
			return nil
		}
		return fiber.Map{"id": key, "url": "/api/v1/players/" + owner + "/media/" + key}
	}
	gallery := []any{}
	for _, key := range p.Gallery {
		gallery = append(gallery, photo(key))
	}
	return fiber.Map{"avatar": photo(p.Avatar), "gallery": gallery, "gallery_limit": 5, "revision": p.Revision}
}
func (a *api) mediaDirectory() string {
	if a.config.MediaDir != "" {
		return a.config.MediaDir
	}
	return "data/profile_media"
}
func (a *api) profileMedia(c fiber.Ctx) error {
	s, ok := a.store.(profileMediaStore)
	if !ok {
		return failure(c, 503, "unavailable", "Profile photos are unavailable.")
	}
	owner := c.Locals("user").(user).ID
	p, err := s.ReadProfileMedia(owner)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"media": mediaView(owner, p)})
}
func (p profileMedia) contains(key string) bool {
	if key == "" {
		return false
	}
	if p.Avatar == key {
		return true
	}
	for _, v := range p.Gallery {
		if v == key {
			return true
		}
	}
	return false
}
func (a *api) profilePhoto(c fiber.Ctx) error {
	owner, key := c.Params("id"), c.Params("key")
	if !validHex(owner, 16) || !validHex(key, 16) {
		return failure(c, 404, "not_found", "Photo not found.")
	}
	s, ok := a.store.(profileMediaStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	p, err := s.ReadProfileMedia(owner)
	if errors.Is(err, errNotFound) {
		return fiber.ErrNotFound
	}
	if err != nil {
		return err
	}
	if !p.contains(key) {
		return failure(c, 404, "not_found", "Photo not found.")
	}
	if a.admin != nil && c.Locals("admin") == nil {
		rows, e := a.admin.db.adminRows(`MATCH(m:AdminMedia {key:$key}) RETURN m.hidden`, map[string]interface{}{"key": owner + "/" + key}, "hidden")
		if e != nil {
			return e
		}
		if len(rows) > 0 && rows[0]["hidden"] == true {
			return fiber.ErrNotFound
		}
	}
	raw, err := os.ReadFile(filepath.Join(a.mediaDirectory(), owner, key+".jpg"))
	if errors.Is(err, os.ErrNotExist) {
		return fiber.ErrNotFound
	}
	if err != nil {
		return err
	}
	c.Set("Content-Type", "image/jpeg")
	return c.Send(raw)
}
func (a *api) changeProfilePhoto(c fiber.Ctx) error {
	s, ok := a.store.(profileMediaStore)
	if !ok {
		return fiber.ErrServiceUnavailable
	}
	owner := c.Locals("user").(user).ID
	if !validHex(owner, 16) {
		return fiber.ErrBadRequest
	}
	kind, key := c.Params("kind"), c.Params("key")
	if kind != "avatar" && kind != "gallery" || key != "" && !validHex(key, 16) {
		return fiber.ErrNotFound
	}
	removing := c.Method() == "DELETE"
	if !removing && ((c.Method() == "PUT" && (kind != "gallery" || key == "")) || (c.Method() == "POST" && key != "")) {
		return fiber.ErrBadRequest
	}
	var encoded []byte
	newKey := ""
	if !removing {
		if len(c.Body()) > profileUploadLimit {
			return failure(c, 413, "image_too_large", "Choose a photo smaller than 8 MB.")
		}
		select {
		case a.mediaSlots <- struct{}{}:
			defer func() { <-a.mediaSlots }()
		default:
			return failure(c, 503, "busy", "Photo processing is busy. Try again shortly.")
		}
		var err error
		encoded, err = normalizeProfileImage(c.Body(), kind == "avatar")
		if err != nil {
			return failure(c, 400, "invalid_image", err.Error())
		}
		id := make([]byte, 16)
		if _, err = rand.Read(id); err != nil {
			return err
		}
		newKey = hex.EncodeToString(id)
	}
	// IDs are generated only by the server and never reused. Each request can
	// safely remove its own uncommitted file on a failed compare-and-set.
	written, committed := false, false
	newPath := filepath.Join(a.mediaDirectory(), owner, newKey+".jpg")
	defer func() {
		if written && !committed {
			_ = os.Remove(newPath)
		}
	}()
	for range 10 {
		p, err := s.ReadProfileMedia(owner)
		if err != nil {
			return err
		}
		oldKey := ""
		if kind == "avatar" {
			if removing && p.Avatar != key {
				return c.JSON(fiber.Map{"media": mediaView(owner, p)})
			}
			oldKey = p.Avatar
			p.Avatar = newKey
		} else {
			index := -1
			for i, v := range p.Gallery {
				if v == key {
					index = i
					break
				}
			}
			if key != "" && index < 0 {
				if removing {
					return c.JSON(fiber.Map{"media": mediaView(owner, p)})
				}
				return failure(c, 409, "photo_changed", "That photo was removed. Refresh your gallery.")
			}
			if removing {
				if index < 0 {
					return fiber.ErrBadRequest
				}
				oldKey = key
				p.Gallery = append(p.Gallery[:index:index], p.Gallery[index+1:]...)
			} else if index >= 0 {
				oldKey = key
				p.Gallery[index] = newKey
			} else {
				if len(p.Gallery) >= 5 {
					return failure(c, 409, "gallery_full", "Your gallery has five photos. Replace or remove one first.")
				}
				p.Gallery = append(p.Gallery, newKey)
			}
		}
		if !removing && !written {
			if err = os.MkdirAll(filepath.Dir(newPath), 0700); err != nil {
				return err
			}
			if err = os.WriteFile(newPath, encoded, 0600); err != nil {
				return err
			}
			written = true
		}
		saved, err := s.WriteProfileMedia(owner, p.Revision, p)
		if err != nil {
			// A lost database response may follow a committed write. Keep the
			// image in that case so the stored reference cannot become broken.
			committed = true
			return err
		}
		if !saved {
			continue
		}
		committed = true
		p.Revision++
		if oldKey != "" {
			_ = os.Remove(filepath.Join(a.mediaDirectory(), owner, oldKey+".jpg"))
		}
		return c.JSON(fiber.Map{"media": mediaView(owner, p)})
	}
	return failure(c, 409, "profile_changed", "Your photos changed. Refresh and try again.")
}

func normalizeProfileImage(raw []byte, avatar bool) ([]byte, error) {
	meta, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil || format != "jpeg" && format != "png" {
		return nil, errors.New("Choose a valid JPG or PNG photo.")
	}
	if meta.Width < 1 || meta.Height < 1 || meta.Width > 8192 || meta.Height > 8192 || int64(meta.Width)*int64(meta.Height) > 20000000 {
		return nil, errors.New("Choose a photo up to 20 megapixels and 8192 pixels per side.")
	}
	src, _, err := image.Decode(bytes.NewReader(raw))
	if err != nil {
		return nil, errors.New("This photo could not be read. Choose another JPG or PNG.")
	}
	orientation := jpegOrientation(raw)
	w, h := meta.Width, meta.Height
	if orientation >= 5 {
		w, h = h, w
	}
	left, top, cw, ch := 0, 0, w, h
	if avatar {
		cw = min(w, h)
		ch = cw
		left = (w - cw) / 2
		top = (h - ch) / 2
	}
	limit := 1600
	if avatar {
		limit = 512
	}
	scale := math.Min(1, float64(limit)/float64(max(cw, ch)))
	ow, oh := max(1, int(float64(cw)*scale)), max(1, int(float64(ch)*scale))
	dst := image.NewRGBA(image.Rect(0, 0, ow, oh))
	pixel := func(x, y int) color.NRGBA {
		x = max(0, min(w-1, x))
		y = max(0, min(h-1, y))
		sx, sy := x, y
		switch orientation {
		case 2:
			sx = meta.Width - 1 - x
		case 3:
			sx, sy = meta.Width-1-x, meta.Height-1-y
		case 4:
			sy = meta.Height - 1 - y
		case 5:
			sx, sy = y, x
		case 6:
			sx, sy = y, meta.Height-1-x
		case 7:
			sx, sy = meta.Width-1-y, meta.Height-1-x
		case 8:
			sx, sy = meta.Width-1-y, x
		}
		v := color.NRGBAModel.Convert(src.At(sx+src.Bounds().Min.X, sy+src.Bounds().Min.Y)).(color.NRGBA)
		// Flatten transparency against pearl; JPEG drops EXIF and other metadata.
		for _, vptr := range []*uint8{&v.R, &v.G, &v.B} {
			*vptr = uint8((int(*vptr)*int(v.A) + 245*(255-int(v.A))) / 255)
		}
		v.A = 255
		return v
	}
	for y := 0; y < oh; y++ {
		fy := float64(top) + (float64(y)+0.5)*float64(ch)/float64(oh) - 0.5
		y0 := int(math.Floor(fy))
		dy := fy - float64(y0)
		for x := 0; x < ow; x++ {
			fx := float64(left) + (float64(x)+0.5)*float64(cw)/float64(ow) - 0.5
			x0 := int(math.Floor(fx))
			dx := fx - float64(x0)
			a, b, c, d := pixel(x0, y0), pixel(x0+1, y0), pixel(x0, y0+1), pixel(x0+1, y0+1)
			mix := func(aa, bb, cc, dd uint8) uint8 {
				return uint8(math.Round((float64(aa)*(1-dx)+float64(bb)*dx)*(1-dy) + (float64(cc)*(1-dx)+float64(dd)*dx)*dy))
			}
			dst.SetRGBA(x, y, color.RGBA{mix(a.R, b.R, c.R, d.R), mix(a.G, b.G, c.G, d.G), mix(a.B, b.B, c.B, d.B), 255})
		}
	}
	var out bytes.Buffer
	if err = jpeg.Encode(&out, dst, &jpeg.Options{Quality: 85}); err != nil {
		return nil, fmt.Errorf("encode photo: %w", err)
	}
	return out.Bytes(), nil
}

// Read only the bounded EXIF orientation tag. No EXIF/GPS is retained in output.
func jpegOrientation(raw []byte) int {
	if len(raw) < 4 || raw[0] != 0xff || raw[1] != 0xd8 {
		return 1
	}
	for pos := 2; pos+4 <= len(raw); {
		if raw[pos] != 0xff {
			return 1
		}
		marker := raw[pos+1]
		pos += 2
		if marker == 0xda || marker == 0xd9 {
			return 1
		}
		if marker == 0xff {
			pos--
			continue
		}
		if marker == 0x01 || marker >= 0xd0 && marker <= 0xd7 {
			continue
		}
		n := int(raw[pos])<<8 | int(raw[pos+1])
		if n < 2 || n > len(raw)-pos {
			return 1
		}
		part := raw[pos+2 : pos+n]
		pos += n
		if marker != 0xe1 || len(part) < 14 || !bytes.Equal(part[:6], []byte("Exif\x00\x00")) {
			continue
		}
		tiff := part[6:]
		little := string(tiff[:2]) == "II"
		if !little && string(tiff[:2]) != "MM" {
			return 1
		}
		read := func(at, size int) uint32 {
			if at < 0 || at > len(tiff)-size {
				return 0
			}
			var v uint32
			for i := 0; i < size; i++ {
				index := i
				if little {
					index = size - 1 - i
				}
				v = v<<8 | uint32(tiff[at+index])
			}
			return v
		}
		if read(2, 2) != 42 {
			return 1
		}
		offset := int(read(4, 4))
		if offset < 8 || offset > len(tiff)-2 {
			return 1
		}
		count := int(read(offset, 2))
		for i := 0; i < count && offset+2+(i+1)*12 <= len(tiff); i++ {
			at := offset + 2 + i*12
			if read(at, 2) == 0x112 && read(at+2, 2) == 3 && read(at+4, 4) == 1 {
				v := int(read(at+8, 2))
				if v >= 1 && v <= 8 {
					return v
				}
			}
		}
	}
	return 1
}

func isProfileUpload(c fiber.Ctx) bool {
	prefix := "/api/v1/profile/media/"
	return (c.Method() == "POST" || c.Method() == "PUT") && strings.HasPrefix(c.Path(), prefix)
}
