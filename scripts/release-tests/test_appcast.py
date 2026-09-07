import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'generate-appcast.sh'

class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.updates = self.root / 'updates with spaces'
        self.updates.mkdir()
        self.trace = self.root / 'args.json'
        tool = self.root / 'generate_appcast'
        tool.write_text('#!/usr/bin/env python3\nimport json, os, sys\nopen(os.environ["MOCK_ARGS"], "w").write(json.dumps(sys.argv[1:]))\n')
        tool.chmod(0o755)
        self.env = dict(os.environ, SPARKLE_BIN_DIR=str(self.root),
                        NOWCAST_DOWNLOAD_URL_PREFIX='https://example.com/updates/', MOCK_ARGS=str(self.trace))

    def run_script(self):
        return subprocess.run(['bash', str(SCRIPT), str(self.updates)], env=self.env, capture_output=True, text=True)

    def test_insecure_and_ambiguous_prefixes_never_invoke_signer(self):
        for url in ['http://example.com/', 'https://user:pass@example.com/', 'https://example.com/?query=x', 'https://example.com/updates']:
            self.env['NOWCAST_DOWNLOAD_URL_PREFIX'] = url
            self.assertNotEqual(self.run_script().returncode, 0, url)
            self.assertFalse(self.trace.exists())

    def test_passes_https_prefix_and_space_containing_path_as_arguments(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.trace.read_text()), ['--download-url-prefix', 'https://example.com/updates/', str(self.updates)])

    def test_missing_tool_fails(self):
        self.env['SPARKLE_BIN_DIR'] = str(self.root / 'missing')
        self.assertNotEqual(self.run_script().returncode, 0)
        self.assertFalse(self.trace.exists())

if __name__ == '__main__':
    unittest.main()
