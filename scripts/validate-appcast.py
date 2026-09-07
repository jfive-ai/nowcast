#!/usr/bin/env python3
"""Reject missing or unsigned update metadata; Sparkle verifies signatures on install."""
import base64
from pathlib import Path
import sys
from urllib.parse import urlsplit
import xml.etree.ElementTree as ET

SIGNATURE = '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'

def validate(directory: Path) -> int:
    count = 0
    for path in directory.glob('*.xml'):
        tree = ET.parse(path)
        for enclosure in tree.iter():
            if enclosure.tag.rsplit('}', 1)[-1] != 'enclosure':
                continue
            url = urlsplit(enclosure.get('url', ''))
            if url.scheme != 'https' or not url.hostname or url.username or url.password:
                raise ValueError(f'{path.name}: update enclosure must use HTTPS without credentials')
            if int(enclosure.get('length', '0')) <= 0:
                raise ValueError(f'{path.name}: update enclosure must declare a positive archive length')
            signature = base64.b64decode(enclosure.get(SIGNATURE, ''), validate=True)
            if len(signature) != 64:
                raise ValueError(f'{path.name}: missing or malformed Ed25519 signature; check the bundle public key against the Keychain signing key')
            count += 1
    if count == 0:
        raise ValueError('No appcast update enclosures were generated')
    return count

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: validate-appcast.py <updates-directory>')
    try:
        count = validate(Path(sys.argv[1]))
    except (ValueError, OSError, ET.ParseError) as error:
        raise SystemExit(str(error))
    print(f'Validated signature metadata for {count} update enclosure(s).')
