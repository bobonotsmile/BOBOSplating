"""Validate the actual GitHub attachment, including a real offline Docker import."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import subprocess
import sys
import tarfile
import tempfile

archive = Path(sys.argv[1]).resolve()
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='release extracted with spaces ', dir=root / 'tests') as temp:
    with tarfile.open(archive, 'r:gz') as bundle:
        for member in bundle.getmembers():
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and '..' not in path.parts
            assert path.parts[0] == 'bobosplating'
            assert member.isdir() or member.isfile(), member.name
            assert not any(x in path.parts for x in ('data', 'certs', 'bin', 'obj', 'splat-backend', 'web-frontend', 'assets'))
        bundle.extractall(temp, filter='data')
    package = Path(temp) / 'bobosplating'
    expected_files = {'.env', 'checksums.txt'}
    for line in (package / 'checksums.txt').read_text().splitlines():
        expected, relative = line.split('  ', 1)
        expected_files.add(relative)
        with (package / relative).open('rb') as source:
            assert hashlib.file_digest(source, 'sha256').hexdigest() == expected, relative
    assert {p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()} == expected_files
    assert (package / '.env').read_bytes() == (package / '.env.example').read_bytes()
    assert 'BOBO_PUBLIC_HOST=CHANGE_ME' in (package / '.env').read_text()
    config = json.loads(subprocess.check_output(['docker', 'compose', 'config', '--format', 'json'], cwd=package, text=True))
    for service in config['services'].values():
        assert 'build' not in service and service['pull_policy'] == 'never'
        for volume in service.get('volumes', []):
            assert Path(volume['source']).is_relative_to(package), volume
    assert config['services']['splat-backend']['runtime'] == 'nvidia'
    print('PASS: extracted package checksums, clean inventory and relocated Compose', flush=True)
    image_archive = package / 'images/bobosplating-linux-amd64.tar.gz'
    subprocess.run(['docker', 'load', '-i', str(image_archive)], check=True)
    for item in json.loads((package / 'images/image-manifest.json').read_text()):
        assert item['Os'] == 'linux' and item['Architecture'] == 'amd64'
        for tag in item['RepoTags']:
            actual = json.loads(subprocess.check_output(['docker', 'image', 'inspect', tag], text=True))[0]
            assert actual['Id'] == item['Id']
    print('PASS: compressed images imported locally; IDs and architecture match manifest', flush=True)
    subprocess.run(['docker', 'run', '--rm', '--pull', 'never', '--entrypoint', 'bash',
                    '--mount', f'type=bind,source={package},target=/package,readonly',
                    'bobosplating-backend:0.1.0-ubuntu24', '-c',
                    'for f in /package/*.sh /package/publish-config/*.sh; do bash -n "$f" || exit; done'], check=True)
    print('PASS: all delivered Bash scripts parse', flush=True)
