"""Refresh generated deployment documentation without rebuilding unchanged images."""
from pathlib import Path
import hashlib
import io
import os
import tarfile
import tempfile
import time

root = Path(__file__).resolve().parent.parent
archive = root / 'publish/BOBOSplating-0.1.0-ubuntu24-amd64.tar.gz'
expanded = root / 'publish/publish-linux-ubuntu'
document = (expanded / '部署说明.md').read_bytes()
doc_name = 'bobosplating/部署说明.md'
checks_name = 'bobosplating/checksums.txt'
with tarfile.open(archive, 'r:gz') as source:
    original_checks = source.extractfile(checks_name).read().decode()
lines = original_checks.splitlines()
assert sum(line.endswith('  部署说明.md') for line in lines) == 1
new_checks = ('\n'.join(
    hashlib.sha256(document).hexdigest() + '  部署说明.md'
    if line.endswith('  部署说明.md') else line for line in lines
) + '\n').encode()
replacement = {doc_name: document, checks_name: new_checks}
fd, temp_name = tempfile.mkstemp(prefix='.docs-refresh-', suffix='.tar.gz', dir=archive.parent)
os.close(fd)
temporary = Path(temp_name)
before = {}
with tarfile.open(archive, 'r:gz') as source, tarfile.open(temporary, 'w:gz') as target:
    for member in source:
        if member.isfile():
            with source.extractfile(member) as stream:
                before[member.name] = hashlib.file_digest(stream, 'sha256').hexdigest()
            if member.name in replacement:
                data = replacement[member.name]
                member.size = len(data)
                member.mtime = int(time.time())
                target.addfile(member, io.BytesIO(data))
            else:
                target.addfile(member, source.extractfile(member))
        else:
            assert member.isdir(), member.name
            target.addfile(member)
after = {}
with tarfile.open(temporary, 'r:gz') as result:
    for member in result:
        if member.isfile():
            with result.extractfile(member) as stream:
                after[member.name] = hashlib.file_digest(stream, 'sha256').hexdigest()
assert before.keys() == after.keys()
for name in before:
    expected = hashlib.sha256(replacement[name]).hexdigest() if name in replacement else before[name]
    assert after[name] == expected, name
for line in new_checks.decode().splitlines():
    expected, relative = line.split('  ', 1)
    assert after['bobosplating/' + relative] == expected, relative
os.replace(temporary, archive)
(expanded / 'checksums.txt').write_bytes(new_checks)
with archive.open('rb') as stream:
    digest = hashlib.file_digest(stream, 'sha256').hexdigest()
Path(str(archive) + '.sha256').write_text(digest + '  ' + archive.name + '\n', encoding='utf-8')
print('PASS: deployment document and its checksum refreshed; all other payloads unchanged')
print('Archive bytes:', archive.stat().st_size)
print('SHA256:', digest)
