"""Repair Godot's non-Gradle provider-authority rewrite before APK signing.

The 4.7.2 exporter rewrites every provider authority to <package>.fileprovider,
including Jetpack Startup. Preserve the FileProvider authority and restore the
Startup provider's distinct <package>.androidx-startup authority.
"""
from __future__ import annotations

import struct
from collections import Counter

STRING = 3
NO_INDEX = 0xFFFFFFFF


def chunks(data: bytes):
    if len(data) < 8 or struct.unpack_from('<HHI', data) != (3, 8, len(data)):
        raise ValueError('Invalid binary Android manifest header')
    offset = 8
    while offset < len(data):
        kind, header, size = struct.unpack_from('<HHI', data, offset)
        if header < 8 or size < header or offset + size > len(data):
            raise ValueError('Invalid Android manifest chunk')
        yield offset, kind, header, size
        offset += size


def _length(data: bytes, offset: int, utf8: bool) -> tuple[int, int]:
    if utf8:
        first = data[offset]
        return (((first & 127) << 8) | data[offset + 1], offset + 2) if first & 128 else (first, offset + 1)
    first = struct.unpack_from('<H', data, offset)[0]
    return (((first & 32767) << 16) | struct.unpack_from('<H', data, offset + 2)[0], offset + 4) if first & 32768 else (first, offset + 2)


def _encode_length(value: int, utf8: bool) -> bytes:
    if utf8:
        return bytes([value]) if value < 128 else bytes([128 | (value >> 8), value & 255])
    return struct.pack('<H', value) if value < 32768 else struct.pack('<HH', 32768 | (value >> 16), value & 65535)


def pool(data: bytes) -> tuple[int, int, bytes, list[str]]:
    for offset, kind, header, size in chunks(data):
        if kind != 1:
            continue
        count, styles, flags, start, style_start = struct.unpack_from('<5I', data, offset + 8)
        if header != 28 or styles or style_start:
            raise ValueError('Unexpected styled manifest string pool')
        utf8 = bool(flags & 256)
        strings: list[str] = []
        for index in range(count):
            position = offset + start + struct.unpack_from('<I', data, offset + header + index * 4)[0]
            length, position = _length(data, position, utf8)
            if utf8:
                length, position = _length(data, position, True)
            strings.append(data[position:position + length * (1 if utf8 else 2)].decode('utf-8' if utf8 else 'utf-16-le'))
        return offset, size, data[offset:offset + header], strings
    raise ValueError('Manifest has no string pool')


def _write_pool(header: bytes, strings: list[str]) -> bytes:
    utf8 = bool(struct.unpack_from('<I', header, 16)[0] & 256)
    content = bytearray()
    offsets: list[int] = []
    for value in strings:
        offsets.append(len(content))
        utf16 = value.encode('utf-16-le')
        content.extend(_encode_length(len(utf16) // 2, utf8))
        if utf8:
            raw = value.encode('utf-8')
            content.extend(_encode_length(len(raw), True))
            content.extend(raw + b'\0')
        else:
            content.extend(utf16 + b'\0\0')
    content.extend(b'\0' * (-len(content) % 4))
    result = bytearray(header)
    start = len(header) + len(strings) * 4
    struct.pack_into('<I', result, 4, start + len(content))
    struct.pack_into('<I', result, 8, len(strings))
    struct.pack_into('<I', result, 16, struct.unpack_from('<I', header, 16)[0] & ~1)
    struct.pack_into('<I', result, 20, start)
    return bytes(result) + struct.pack('<' + 'I' * len(offsets), *offsets) + bytes(content)


def elements(data: bytes, strings: list[str]):
    for offset, kind, _, _ in chunks(data):
        if kind != 0x102:
            continue
        extension = offset + 16
        tag = strings[struct.unpack_from('<I', data, extension + 4)[0]]
        start, size, count = struct.unpack_from('<HHH', data, extension + 8)
        if size != 20:
            raise ValueError('Unexpected manifest attribute size')
        attributes = {}
        for index in range(count):
            position = extension + start + index * size
            namespace, name, raw, _, _, kind, value = struct.unpack_from('<IIIHBBI', data, position)
            attributes[strings[name]] = (strings[value] if kind == STRING else value, raw, value, position, namespace)
        yield tag, attributes


def provider_authorities(data: bytes) -> dict[str, str]:
    strings = pool(data)[3]
    return {str(attrs['name'][0]): str(attrs['authorities'][0])
            for tag, attrs in elements(data, strings) if tag == 'provider'}


def fix_provider_authorities(data: bytes) -> bytes:
    offset, size, header, strings = pool(data)
    items = list(elements(data, strings))
    package = next(str(attrs['package'][0]) for tag, attrs in items if tag == 'manifest')
    expected = {'androidx.core.content.FileProvider': package + '.fileprovider',
                'androidx.startup.InitializationProvider': package + '.androidx-startup'}
    providers = [(str(attrs['name'][0]), attrs['authorities']) for tag, attrs in items if tag == 'provider']
    if {name for name, _ in providers} != set(expected):
        raise ValueError('Unexpected provider set; review Android packaging before release')
    patched = bytearray(data)
    for name, attribute in providers:
        value, raw, index, position, _ = attribute
        if value == expected[name]:
            continue
        # A new entry also works if a future exporter shares the wrong string
        # index between providers. Patch references, never the shared value.
        strings.append(expected[name])
        index = len(strings) - 1
        if raw != NO_INDEX:
            struct.pack_into('<I', patched, position + 8, index)
        struct.pack_into('<I', patched, position + 16, index)
    result = bytearray(bytes(patched[:offset]) + _write_pool(header, strings) + bytes(patched[offset + size:]))
    struct.pack_into('<I', result, 4, len(result))
    authorities = provider_authorities(bytes(result))
    if authorities != expected or any(count > 1 for count in Counter(authorities.values()).values()):
        raise ValueError('Android provider authorities are not unique')
    return bytes(result)
