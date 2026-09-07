"""Workflow tests use fake platform tools; they never submit to Apple."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'notarize.sh'
MOCK = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['MOCK_TRACE'], 'a') as out:
    out.write(json.dumps([name, *args]) + '\n')
if name == 'security':
    if os.environ.get('MOCK_MIXED_IDENTITY'):
        print('1) HASH \"Developer ID Application: Other (ZZZZZ99999)\"')
        print('2) HASH \"Apple Development: Nowcast (ABCDE12345)\"')
    elif not os.environ.get('MOCK_NO_IDENTITY'):
        print('1) HASH "Developer ID Application: Nowcast (ABCDE12345)"')
elif name == 'xcodebuild' and '-exportArchive' in args:
    (Path(args[args.index('-exportPath') + 1]) / 'Nowcast.app').mkdir(parents=True)
elif name == 'codesign' and '-dv' in args:
    print('Authority=Developer ID Application: Nowcast (ABCDE12345)')
    print('TeamIdentifier=' + os.environ.get('MOCK_TEAM', 'ABCDE12345'))
    print('CodeDirectory flags=0x10000(runtime)')
elif name == 'xcrun' and args[:2] == ['notarytool', 'submit']:
    print(json.dumps({'status': os.environ.get('MOCK_STATUS', 'Accepted')}))
'''

class NotarizeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        tools = self.root / 'tools'
        tools.mkdir()
        for name in ['xcodegen', 'xcodebuild', 'xcrun', 'security', 'codesign', 'spctl', 'ditto']:
            p = tools / name
            p.write_text(MOCK)
            p.chmod(0o755)
        self.trace = self.root / 'trace.jsonl'
        self.env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                        NOWCAST_DEVELOPMENT_TEAM='ABCDE12345', NOWCAST_NOTARY_PROFILE='test-profile',
                        NOWCAST_RELEASE_VERSION='1.2.0', NOWCAST_BUILD_NUMBER='42',
                        NOWCAST_APPCAST_URL='https://example.com/appcast.xml',
                        NOWCAST_SPARKLE_PUBLIC_KEY=base64.b64encode(bytes([1] * 32)).decode(),
                        NOWCAST_RELEASE_DIR=str(self.root / 'release'), MOCK_TRACE=str(self.trace))

    def run_script(self, *args):
        return subprocess.run(['bash', str(SCRIPT), *args], env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(s) for s in self.trace.read_text().splitlines()] if self.trace.exists() else []

    def test_invalid_config_never_invokes_platform_tools(self):
        self.env['NOWCAST_DEVELOPMENT_TEAM'] = 'invalid'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_validation_does_not_access_keychain(self):
        self.assertEqual(self.run_script('--validate-config').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_no_identity_stops_before_build(self):
        self.env['MOCK_NO_IDENTITY'] = '1'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual([c[0] for c in self.calls()], ['security'])

    def test_developer_id_must_match_team_on_the_same_identity(self):
        self.env['MOCK_MIXED_IDENTITY'] = '1'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual([c[0] for c in self.calls()], ['security'])

    def test_wrong_signing_team_stops_before_submission(self):
        self.env['MOCK_TEAM'] = 'WRONG12345'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(any(c[:3] == ['xcrun', 'notarytool', 'submit'] for c in self.calls()))

    def test_rejected_submission_never_staples_or_assesses(self):
        self.env['MOCK_STATUS'] = 'Invalid'
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(any(c[0] == 'spctl' or c[:2] == ['xcrun', 'stapler'] for c in self.calls()))

    def test_success_repackages_only_after_stapling_and_gatekeeper(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        ditto = [i for i, c in enumerate(calls) if c[0] == 'ditto']
        staple = next(i for i, c in enumerate(calls) if c[:3] == ['xcrun', 'stapler', 'staple'])
        assess = next(i for i, c in enumerate(calls) if c[0] == 'spctl')
        self.assertEqual(len(ditto), 2)
        self.assertLess(ditto[0], staple)
        self.assertLess(staple, assess)
        self.assertLess(assess, ditto[1])
        archive = next(c for c in calls if c[0] == 'xcodebuild' and 'archive' in c)
        self.assertIn('MARKETING_VERSION=1.2.0', archive)
        self.assertIn('CURRENT_PROJECT_VERSION=42', archive)

    def test_release_rejects_insecure_or_unconfigured_updater(self):
        self.env['NOWCAST_APPCAST_URL'] = 'http://example.com/appcast.xml'
        self.assertNotEqual(self.run_script('--validate-config').returncode, 0)
        self.assertEqual(self.calls(), [])
        self.env['NOWCAST_APPCAST_URL'] = 'https://example.com/appcast.xml'
        self.env['NOWCAST_SPARKLE_PUBLIC_KEY'] = 'invalid'
        self.assertNotEqual(self.run_script('--validate-config').returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_existing_output_is_not_overwritten(self):
        (self.root / 'release').mkdir()
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertEqual(self.calls(), [])

if __name__ == '__main__':
    unittest.main()
