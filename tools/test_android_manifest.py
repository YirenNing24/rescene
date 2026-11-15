"""Binary manifest regressions using the actual export template and Android parser."""
import struct
import unittest
import zipfile
from pathlib import Path

from android_manifest import _write_pool, chunks, elements, fix_provider_authorities, pool, provider_authorities

ROOT = Path(__file__).resolve().parents[1]


class ManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with zipfile.ZipFile(ROOT / 'builds/templates/android_release.apk') as apk:
            cls.original = apk.read('AndroidManifest.xml')

    def bad_export(self, shared_index=False):
        offset, size, header, strings = pool(self.original)
        first = None
        data = bytearray(self.original)
        for tag, attrs in elements(self.original, strings):
            if tag != 'provider':
                continue
            _, raw, index, position, _ = attrs['authorities']
            strings[index] = 'com.rescene.rhythm.fileprovider'
            if first is None:
                first = index
            elif shared_index:
                if raw != 0xFFFFFFFF:
                    struct.pack_into('<I', data, position + 8, first)
                struct.pack_into('<I', data, position + 16, first)
        # Godot also replaces the package attribute; preserve all other strings.
        for tag, attrs in elements(self.original, pool(self.original)[3]):
            if tag == 'manifest':
                strings[attrs['package'][2]] = 'com.rescene.rhythm'
        result = bytearray(data[:offset] + _write_pool(header, strings) + data[offset + size:])
        struct.pack_into('<I', result, 4, len(result))
        return bytes(result)

    def test_duplicate_authorities_are_distinct_after_repair(self):
        for shared in (False, True):
            with self.subTest(shared_index=shared):
                original = self.bad_export(shared)
                self.assertEqual(len(set(provider_authorities(original).values())), 1)
                fixed = fix_provider_authorities(original)
                self.assertEqual(provider_authorities(fixed), {
                    'androidx.core.content.FileProvider': 'com.rescene.rhythm.fileprovider',
                    'androidx.startup.InitializationProvider': 'com.rescene.rhythm.androidx-startup'})
                self.assertEqual(fix_provider_authorities(fixed), fixed)
                # All other attributes, permissions and resource IDs are unchanged.
                before = [(tag, {key: attr[0] for key, attr in attrs.items()})
                          for tag, attrs in elements(original, pool(original)[3])]
                after = [(tag, {key: attr[0] for key, attr in attrs.items()})
                         for tag, attrs in elements(fixed, pool(fixed)[3])]
                for _, attrs in before:
                    if attrs.get('name') == 'androidx.startup.InitializationProvider':
                        attrs['authorities'] = 'com.rescene.rhythm.androidx-startup'
                self.assertEqual(before, after)
                self.assertEqual([original[o:o+n] for o,k,_,n in chunks(original) if k==0x180],
                                 [fixed[o:o+n] for o,k,_,n in chunks(fixed) if k==0x180])

    def test_unknown_or_truncated_manifest_is_rejected(self):
        for raw in (b'', self.original[:-1], b'not an Android manifest'):
            with self.subTest(length=len(raw)), self.assertRaises(ValueError):
                fix_provider_authorities(raw)

    def test_utf8_pool_and_unicode_survive(self):
        offset, size, header, strings = pool(self.original)
        header = bytearray(header)
        struct.pack_into('<I', header, 16, 256)
        strings.append('RESCÉNE 🌙 ' * 20)
        data = bytearray(self.original[:offset] + _write_pool(bytes(header), strings) + self.original[offset + size:])
        struct.pack_into('<I', data, 4, len(data))
        fixed = fix_provider_authorities(bytes(data))
        self.assertIn('RESCÉNE 🌙 ' * 20, pool(fixed)[3])
        self.assertEqual(provider_authorities(fixed)['androidx.startup.InitializationProvider'], 'com.godot.game.androidx-startup')


if __name__ == '__main__':
    unittest.main()
