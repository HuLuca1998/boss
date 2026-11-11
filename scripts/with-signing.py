#!/usr/bin/env python3
"""Run a trusted build command with the repository's encrypted signing identity."""
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    # Never echo command arguments: security receives temporary passwords as arguments.
    label=" ".join(args[:2])
    print(f"Signing setup: {label}", flush=True)
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60, **kwargs)

def main():
    password = os.environ.pop('BOSS_SIGNING_PASSWORD', '')
    if not password or len(sys.argv) < 2:
        raise SystemExit('Signing password and build command are required')
    original = run('security', 'list-keychains', '-d', 'user').stdout.decode()
    keychains = [line.strip().strip('"') for line in original.splitlines() if line.strip()]
    certificate = ROOT / 'signing/BossAssistant.cer'
    ci = os.environ.get('GITHUB_ACTIONS') == 'true'
    trust_command = ['sudo', '-n', 'security'] if ci else ['security']
    trust_domain = ['-d'] if ci else []
    expected = (ROOT / 'BossAssistant/SigningIdentity.txt').read_text().strip()
    with tempfile.TemporaryDirectory(prefix='boss-signing-') as folder:
        directory = Path(folder)
        identity = directory / 'identity.p12'
        keychain = str(directory / 'build.keychain-db')
        keychain_password = secrets.token_urlsafe(48)
        trusted = False
        try:
            run('openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2', '-iter', '600000',
                '-in', str(ROOT / 'signing/BossAssistant.p12.enc'), '-out', str(identity),
                '-pass', 'stdin', input=password.encode())
            run('security', 'create-keychain', '-p', keychain_password, keychain)
            run('security', 'set-keychain-settings', '-lut', '21600', keychain)
            run('security', 'unlock-keychain', '-p', keychain_password, keychain)
            run('security', 'import', str(identity), '-k', keychain, '-P', password,
                '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            identity.unlink()
            run('security', 'list-keychains', '-d', 'user', '-s', keychain, *keychains)
            run(*trust_command, 'add-trusted-cert', *trust_domain, '-r', 'trustRoot', '-p', 'codeSign', '-k', keychain, str(certificate))
            trusted = True
            run('security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:',
                '-s', '-k', keychain_password, keychain)
            identities = run('security', 'find-identity', '-v', '-p', 'codesigning', keychain).stdout.decode()
            if expected not in identities:
                raise RuntimeError('Imported identity does not match pinned fingerprint')
            print('Pinned signing identity verified', flush=True)
            return subprocess.run(sys.argv[1:], cwd=ROOT).returncode
        finally:
            if trusted:
                subprocess.run([*trust_command, 'remove-trusted-cert', *trust_domain, str(certificate)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *keychains], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
            subprocess.run(['security', 'delete-keychain', keychain], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
        # CalledProcessError includes argv (and passwords); intentionally suppress it.
        raise SystemExit('Signing setup failed; check password, certificate, OpenSSL and keychain access')
