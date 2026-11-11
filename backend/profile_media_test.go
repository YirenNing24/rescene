package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"hash/crc32"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/gofiber/fiber/v3"
	"github.com/valyala/fasthttp"
	"golang.org/x/crypto/bcrypt"
)

func photoBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 80, 60))
	for y := 0; y < 60; y++ {
		for x := 0; x < 80; x++ {
			img.Set(x, y, color.RGBA{uint8(x * 3), uint8(y * 4), 180, 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}
func photoCall(t *testing.T, app *fiber.App, method, path, token string, raw []byte) (int, []byte) {
	t.Helper()
	req := httptest.NewRequest(method, path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/octet-stream")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := app.Test(req, fiber.TestConfig{Timeout: 10_000_000_000})
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatal(err)
	}
	return res.StatusCode, body
}
func mediaResult(t *testing.T, raw []byte) map[string]any {
	t.Helper()
	var result map[string]any
	if err := json.Unmarshal(raw, &result); err != nil {
		t.Fatal(err)
	}
	m, ok := result["media"].(map[string]any)
	if !ok {
		t.Fatalf("missing media: %s", raw)
	}
	return m
}
func photoTestApp(t *testing.T, s *graphStore, dir string) *fiber.App {
	t.Helper()
	cfg := testConfig()
	cfg.MediaDir = dir
	app, err := newApp(s, cfg, bcrypt.MinCost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = app.Shutdown() })
	return app
}
func photoLogin(t *testing.T, app *fiber.App, name string) (string, string) {
	t.Helper()
	status, body, _ := request(t, app, "POST", "/api/v1/auth/register", creds(name, "test-photo-password"), "")
	requireStatus(t, status, 201)
	return body["access_token"].(string), body["user"].(map[string]any)["id"].(string)
}
func TestProfileAvatarAndFivePhotoGallery(t *testing.T) {
	s := testStore(t)
	dir := t.TempDir()
	app := photoTestApp(t, s, dir)
	token, owner := photoLogin(t, app, "PhotoOwner")
	other, otherID := photoLogin(t, app, "PhotoViewer")
	photo := photoBytes(t)
	status, raw := photoCall(t, app, "POST", "/api/v1/profile/media/avatar", "", photo)
	requireStatus(t, status, 401)
	status, raw = photoCall(t, app, "POST", "/api/v1/profile/media/avatar", token, photo)
	requireStatus(t, status, 200)
	avatar := mediaResult(t, raw)["avatar"].(map[string]any)
	avatarURL := avatar["url"].(string)
	avatarID := avatar["id"].(string)
	status, raw = photoCall(t, app, "GET", avatarURL, other, nil)
	requireStatus(t, status, 200)
	meta, format, err := image.DecodeConfig(bytes.NewReader(raw))
	if err != nil || format != "jpeg" || meta.Width != 60 || meta.Height != 60 {
		t.Fatal("avatar not normalized/cropped", meta, format, err)
	}
	status, _ = photoCall(t, app, "GET", avatarURL, "", nil)
	requireStatus(t, status, 401)
	status, _ = photoCall(t, app, "GET", strings.Replace(avatarURL, owner, otherID, 1), other, nil)
	requireStatus(t, status, 404)
	var gallery []any
	for range 5 {
		status, raw = photoCall(t, app, "POST", "/api/v1/profile/media/gallery", token, photo)
		requireStatus(t, status, 200)
		gallery = mediaResult(t, raw)["gallery"].([]any)
	}
	status, _ = photoCall(t, app, "POST", "/api/v1/profile/media/gallery", token, photo)
	requireStatus(t, status, 409)
	old := gallery[0].(map[string]any)
	oldID, oldURL := old["id"].(string), old["url"].(string)
	status, raw = photoCall(t, app, "PUT", "/api/v1/profile/media/gallery/"+oldID, token, photo)
	requireStatus(t, status, 200)
	gallery = mediaResult(t, raw)["gallery"].([]any)
	if len(gallery) != 5 || gallery[0].(map[string]any)["id"] == oldID {
		t.Fatal("replacement did not retain five slots")
	}
	status, _ = photoCall(t, app, "GET", oldURL, token, nil)
	requireStatus(t, status, 404)
	if _, err = os.Stat(filepath.Join(dir, owner, oldID+".jpg")); !os.IsNotExist(err) {
		t.Fatal("replaced image remains on disk")
	}
	first := gallery[0].(map[string]any)["id"].(string)
	status, raw = photoCall(t, app, "DELETE", "/api/v1/profile/media/gallery/"+first, other, nil)
	requireStatus(t, status, 200)
	if len(mediaResult(t, raw)["gallery"].([]any)) != 0 {
		t.Fatal("another account affected owner's gallery")
	}
	status, raw = photoCall(t, app, "DELETE", "/api/v1/profile/media/gallery/"+first, token, nil)
	requireStatus(t, status, 200)
	if len(mediaResult(t, raw)["gallery"].([]any)) != 4 {
		t.Fatal("delete did not free a slot")
	}
	status, raw = photoCall(t, app, "DELETE", "/api/v1/profile/media/gallery/"+first, token, nil)
	requireStatus(t, status, 200)
	if len(mediaResult(t, raw)["gallery"].([]any)) != 4 {
		t.Fatal("duplicate delete removed a different photo")
	}
	// Restart against the same graph and persistent image directory.
	second, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	app2 := photoTestApp(t, second, dir)
	status, raw = photoCall(t, app2, "GET", "/api/v1/profile/media", token, nil)
	requireStatus(t, status, 200)
	if len(mediaResult(t, raw)["gallery"].([]any)) != 4 {
		t.Fatal("gallery not persistent")
	}
	status, body, _ := request(t, app2, "GET", "/api/v1/players/"+owner, nil, other)
	requireStatus(t, status, 200)
	public := body["profile"].(map[string]any)["media"].(map[string]any)
	if len(public["gallery"].([]any)) != 4 || public["avatar"] == nil {
		t.Fatal("public profile lacks photos")
	}
	status, _ = photoCall(t, app2, "GET", avatarURL, token, nil)
	requireStatus(t, status, 200)
	status, raw = photoCall(t, app2, "DELETE", "/api/v1/profile/media/avatar/"+avatarID, token, nil)
	requireStatus(t, status, 200)
	if mediaResult(t, raw)["avatar"] != nil {
		t.Fatal("avatar not removed")
	}
	status, _ = photoCall(t, app2, "GET", avatarURL, other, nil)
	requireStatus(t, status, 404)
}
func TestConcurrentGalleryUploadsCannotExceedFive(t *testing.T) {
	s := testStore(t)
	dir := t.TempDir()
	one := photoTestApp(t, s, dir)
	token, owner := photoLogin(t, one, "PhotoConcurrent")
	raw := photoBytes(t)
	for range 4 {
		status, _ := photoCall(t, one, "POST", "/api/v1/profile/media/gallery", token, raw)
		requireStatus(t, status, 200)
	}
	other, err := openStore(os.Getenv("FALKORDB_TEST_URL"), s.graph.Id)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	two := photoTestApp(t, other, dir)
	start := make(chan struct{})
	codes := make(chan int, 2)
	var wg sync.WaitGroup
	for _, app := range []*fiber.App{one, two} {
		wg.Go(func() {
			<-start
			status, _ := photoCall(t, app, "POST", "/api/v1/profile/media/gallery", token, raw)
			codes <- status
		})
	}
	close(start)
	wg.Wait()
	close(codes)
	success := 0
	for code := range codes {
		if code == 200 {
			success++
		} else if code != 409 {
			t.Fatal("unexpected upload status", code)
		}
	}
	p, err := s.ReadProfileMedia(owner)
	if err != nil || len(p.Gallery) != 5 || success != 1 {
		t.Fatal("concurrent limit failed", len(p.Gallery), success, err)
	}
	files, err := os.ReadDir(filepath.Join(dir, owner))
	if err != nil || len(files) != 5 {
		t.Fatal("failed upload left an unreferenced image", len(files), err)
	}
}
func TestPhotoValidationAndPhoneOrientation(t *testing.T) {
	for _, raw := range [][]byte{[]byte("<svg onload='bad'>"), []byte("not an image"), {0xff, 0xd8, 0xff}} {
		if _, err := normalizeProfileImage(raw, false); err == nil {
			t.Fatal("invalid image accepted")
		}
	}
	bomb := photoBytes(t)
	binary.BigEndian.PutUint32(bomb[16:20], 8193)
	binary.BigEndian.PutUint32(bomb[29:33], crc32.ChecksumIEEE(bomb[12:29]))
	if _, err := normalizeProfileImage(bomb, false); err == nil {
		t.Fatal("oversized dimensions accepted")
	}
	img := image.NewRGBA(image.Rect(0, 0, 80, 40))
	for y := 0; y < 40; y++ {
		for x := 0; x < 80; x++ {
			if x < 40 {
				img.Set(x, y, color.RGBA{255, 0, 0, 255})
			} else {
				img.Set(x, y, color.RGBA{0, 0, 255, 255})
			}
		}
	}
	var encoded bytes.Buffer
	_ = jpeg.Encode(&encoded, img, &jpeg.Options{Quality: 100})
	for orientation := 1; orientation <= 8; orientation++ {
		exif := []byte{'E', 'x', 'i', 'f', 0, 0, 'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0, byte(orientation), 0, 0, 0, 0, 0, 0, 0}
		segment := []byte{0xff, 0xe1, byte((len(exif) + 2) >> 8), byte(len(exif) + 2)}
		segment = append(segment, exif...)
		raw := append([]byte{}, encoded.Bytes()[:2]...)
		raw = append(raw, segment...)
		raw = append(raw, encoded.Bytes()[2:]...)
		out, err := normalizeProfileImage(raw, false)
		if err != nil {
			t.Fatal(err)
		}
		decoded, _, err := image.Decode(bytes.NewReader(out))
		if err != nil {
			t.Fatal(err)
		}
		w, h := 80, 40
		if orientation >= 5 {
			w, h = h, w
		}
		if decoded.Bounds().Dx() != w || decoded.Bounds().Dy() != h {
			t.Fatal("phone orientation dimensions wrong", orientation)
		}
		if bytes.Contains(out, []byte("Exif")) {
			t.Fatal("metadata retained")
		}
		if orientation == 6 {
			r, _, b, _ := decoded.At(20, 10).RGBA()
			if r < b {
				t.Fatal("rotated phone image flipped")
			}
		}
	}
}
func TestPhotoUploadLimitsPreserveOtherBodyLimits(t *testing.T) {
	s := testStore(t)
	app := photoTestApp(t, s, t.TempDir())
	token, _ := photoLogin(t, app, "PhotoLimits")
	tooLarge := httptest.NewRequest("POST", "/api/v1/profile/media/gallery", bytes.NewReader(bytes.Repeat([]byte{'x'}, profileUploadLimit+1)))
	// Test reports the body-parser error directly; the listener maps it to 413.
	if _, err := app.Test(tooLarge); !errors.Is(err, fasthttp.ErrBodyTooLarge) {
		t.Fatal("upload parser limit not enforced", err)
	}
	for _, tc := range []struct {
		path string
		raw  []byte
		want int
	}{{"/api/v1/profile/media/avatar", []byte("bad"), 400}, {"/api/v1/auth/login", bytes.Repeat([]byte{'x'}, 5000), 413}, {"/api/v1/runs/" + fmt.Sprintf("%032d", 0) + "/complete", bytes.Repeat([]byte{'x'}, 1048577), 413}} {
		status, _ := photoCall(t, app, "POST", tc.path, token, tc.raw)
		requireStatus(t, status, tc.want)
	}
}
