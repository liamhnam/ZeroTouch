#!/usr/bin/env python3
"""Build dist/autounattend.xml with the schneegans.de unattend generator.

The generator supplies the tested plumbing (PE-stage script runner, script
extraction, logging). This profile adds:
  src/pe.cmd           - whole-disk install on the single internal disk + reinstall guard
  src/computername.ps1 - GOODM-<serial|MAC>
  src/specialize.ps1   - firewall, Windows Update, Defender policy, power plan
  src/firstlogon.ps1   - permanent auto-logon, boot order, hand-off to the USB payload

The account name is sent as a placeholder and substituted locally.
Usage: python3 build.py
"""
import html
import pathlib
import re
import urllib.parse
import urllib.request

USERNAME = 'GOODM'
PLACEHOLDER = 'ZZUSERZZ'
GENERATOR = 'https://schneegans.de/windows/unattend-generator/'
ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / 'src'


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': 'AutoInstaller-build'})
    return urllib.request.urlopen(request, timeout=60).read()


def form_defaults(page):
    """Default values of the generator's main form, as a browser would submit them."""
    start = page.find('<form action="." method="get">')
    form = page[start:page.find('</form>', start)]
    values = {}
    for match in re.finditer(r'<input\b([^>]*)>', form):
        attrs = match.group(1)
        name = re.search(r'name="([^"]*)"', attrs)
        if not name:
            continue
        kind = (re.search(r'type="([^"]*)"', attrs) or [None, 'text'])[1]
        value = html.unescape((re.search(r'value="([^"]*)"', attrs) or [None, ''])[1])
        if kind in ('checkbox', 'radio'):
            if 'checked' in attrs:
                values.setdefault(name.group(1), value)
        elif kind not in ('submit', 'button', 'file'):
            values.setdefault(name.group(1), value)
    for match in re.finditer(r'<textarea\b([^>]*)>(.*?)</textarea>', form, re.S):
        name = re.search(r'name="([^"]*)"', match.group(1)).group(1)
        values.setdefault(name, html.unescape(match.group(2)))
    for match in re.finditer(r'<select\b([^>]*)>(.*?)</select>', form, re.S):
        name = re.search(r'name="([^"]*)"', match.group(1)).group(1)
        options = re.findall(r'<option([^>]*)value="([^"]*)"', match.group(2))
        selected = [value for attrs, value in options if 'selected' in attrs] or [options[0][1]]
        values.setdefault(name, html.unescape(selected[0]))
    return values


def main():
    values = form_defaults(fetch(GENERATOR).decode('utf-8'))
    for name in ('UseKeyboard2', 'UseKeyboard3', 'TargetDiskNoPartitions', 'TargetDiskIndex',
                 'PauseBeforeFormatting', 'PauseBeforeReboot', 'ObscurePasswords'):
        values.pop(name, None)
    values.update({
        # Region: English UI (the tiny11 image is en-US only), Vietnam region and time zone
        'LanguageMode': 'Unattended', 'UILanguage': 'en-US', 'Locale': 'en-US', 'Keyboard': '00000409',
        'GeoLocation': '251', 'TimeZoneMode': 'Explicit', 'TimeZone': 'SE Asia Standard Time',
        'ProcessorArchitecture': 'amd64',
        'BypassRequirementsCheck': 'true', 'BypassNetworkCheck': 'true',
        'ComputerNameMode': 'Script', 'ComputerNameScript': (SRC / 'computername.ps1').read_text(),
        # Edition: generic Pro key (no activation), first image in install.wim/esd
        'WindowsEditionMode': 'Generic', 'WindowsEdition': 'pro',
        'InstallFromMode': 'Index', 'InstallFromIndex': '1',
        # PE stage: our own script (whole internal disk, GPT, no recovery partition)
        'PEMode': 'Script', 'PEScript': (SRC / 'pe.cmd').read_text(),
        'PartitionMode': 'Unattended', 'PartitionLayout': 'GPT', 'RecoveryMode': 'None',
        'DisableDefender': 'true',
        # Single administrator without password, auto-logon
        'UserAccountMode': 'Unattended',
        'AccountName0': PLACEHOLDER, 'AccountDisplayName0': PLACEHOLDER,
        'AccountPassword0': '', 'AccountGroup0': 'Administrators',
        'AutoLogonMode': 'Own', 'PasswordExpirationMode': 'Unlimited', 'LockoutMode': 'Disabled',
        'ExpressSettings': 'DisableAll', 'WifiMode': 'Skip',
        # Tweaks
        'DisableWindowsUpdate': 'true', 'PreventDeviceEncryption': 'true', 'DisableFastStartup': 'true',
        'DisableSmartScreen': 'true', 'DisableAutomaticRestartSignOn': 'true',
        # Custom scripts
        'SystemScript0': (SRC / 'specialize.ps1').read_text(), 'SystemScriptType0': 'Ps1',
        'FirstLogonScript0': (SRC / 'firstlogon.ps1').read_text(), 'FirstLogonScriptType0': 'Ps1',
    })
    for index in range(1, 5):
        values.update({f'AccountName{index}': '', f'AccountDisplayName{index}': '', f'AccountPassword{index}': ''})

    query = urllib.parse.urlencode(sorted(values.items()))
    xml = fetch(GENERATOR + 'download/?' + query).decode('utf-8')
    if '<unattend' not in xml:
        raise SystemExit('Generator did not return an answer file:\n' + xml[:2000])

    # The generator embeds the full query (incl. our scripts) as a comment; drop it.
    xml = re.sub(r'<!--https://schneegans\.de/windows/unattend-generator/\?.*?-->\s*', '', xml, count=1, flags=re.S)
    xml = xml.replace(PLACEHOLDER, USERNAME)

    out = ROOT / 'dist' / 'autounattend.xml'
    out.parent.mkdir(exist_ok=True)
    out.write_bytes(xml.encode('utf-8'))
    print(f'Wrote {out} ({len(xml)} bytes)')


if __name__ == '__main__':
    main()
