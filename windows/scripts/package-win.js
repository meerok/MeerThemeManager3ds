// Builds the Windows x64 app (MtM3.exe) and sets its icon + version info with resedit (no Wine needed).
const path = require('path');
const fs = require('fs');
const { packager } = require('@electron/packager');
const ResEdit = require('resedit');

(async () => {
  const root = path.join(__dirname, '..');
  const pkg = require(path.join(root, 'package.json'));
  const [appPath] = await packager({
    dir: root,
    out: path.join(root, 'dist'),
    name: 'MtM3',
    executableName: 'MtM3',
    platform: 'win32',
    arch: 'x64',
    overwrite: true,
    asar: false,
    prune: true,
    ignore: [/^\/dist/, /^\/test/, /^\/scripts/, /^\/\.git/, /\.md$/],
    appCopyright: 'Meer',
    appVersion: pkg.version,
  });
  const exe = path.join(appPath, 'MtM3.exe');
  const data = fs.readFileSync(exe);
  const res = ResEdit.NtExecutableResource.from(ResEdit.NtExecutable.from(data, { ignoreCert: true }));
  const exeObj = ResEdit.NtExecutable.from(data, { ignoreCert: true });
  const resources = ResEdit.NtExecutableResource.from(exeObj);
  const iconFile = ResEdit.Data.IconFile.from(fs.readFileSync(path.join(root, 'assets', 'icon.ico')));
  ResEdit.Resource.IconGroupEntry.replaceIconsForResource(resources.entries, 1, 1033, iconFile.icons.map((i) => i.data));
  const vi = ResEdit.Resource.VersionInfo.fromEntries(resources.entries)[0];
  const [maj, min, pat] = pkg.version.split('.').map(Number);
  vi.setFileVersion(maj, min, pat, 0, 1033);
  vi.setProductVersion(maj, min, pat, 0, 1033);
  vi.setStringValues({ lang: 1033, codepage: 1200 }, {
    FileDescription: 'Meer Theme Manager 3ds',
    ProductName: 'Meer Theme Manager 3ds (MtM3)',
    CompanyName: 'Meer',
    LegalCopyright: '© Meer — MIT License',
    OriginalFilename: 'MtM3.exe',
    InternalName: 'MtM3',
  });
  vi.outputToResourceEntries(resources.entries);
  resources.outputResource(exeObj);
  fs.writeFileSync(exe, Buffer.from(exeObj.generate()));
  void res;
  console.log('Built', exe);
})().catch((e) => { console.error(e); process.exit(1); });
