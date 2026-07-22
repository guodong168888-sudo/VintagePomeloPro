const COVER_PRIORITY: string[] = [
  'cover.png', 'cover.jpg', 'cover.jpeg', 'cover.webp',
  'folder.png', 'folder.jpg', 'folder.jpeg', 'folder.webp'
];

const HELPER_TOKENS: string[] = [
  'unins', 'uninstall', 'setup', 'install', 'crash', 'report',
  'crashhandler', 'werfault', 'cefsubprocess', 'vc_redist', 'vcredist',
  'redist', 'dxsetup', 'dotnet', 'update', 'updater'
];

export function catalogFileName(path: string): string {
  const normalized = path.replace(/\\/g, '/');
  const index = normalized.lastIndexOf('/');
  return index >= 0 ? normalized.substring(index + 1) : normalized;
}

export function catalogNameWithoutExtension(name: string): string {
  const index = name.lastIndexOf('.');
  return index > 0 ? name.substring(0, index) : name;
}

function comparableName(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '');
}

export function chooseExecutablePath(directory: string, candidates: string[]): string {
  if (candidates.length === 0) return '';
  const directoryName = comparableName(catalogFileName(directory));
  const sameName = candidates.find((path: string) =>
    comparableName(catalogNameWithoutExtension(catalogFileName(path))) === directoryName);
  if (sameName) return sameName;
  const preferred = candidates.filter((path: string) => {
    const lower = catalogFileName(path).toLowerCase();
    return !HELPER_TOKENS.some((token: string) => lower.includes(token));
  });
  if (preferred.length === 1) return preferred[0];
  const normalizedDirectory = directory.replace(/\\/g, '/').replace(/\/+$/, '');
  const rootCandidates = preferred.filter((path: string) => {
    const normalizedPath = path.replace(/\\/g, '/');
    const separator = normalizedPath.lastIndexOf('/');
    return separator > 0 && normalizedPath.substring(0, separator) === normalizedDirectory;
  });
  if (rootCandidates.length === 1) return rootCandidates[0];
  // Versioned directories usually keep the executable's stable basename,
  // e.g. palmod2.0/palmod.exe. A unique prefix match is deterministic and
  // avoids presenting a non-launchable card merely because a launcher also
  // exists beside the actual program.
  const versionedMatches = preferred.filter((path: string) => {
    const executableName = comparableName(catalogNameWithoutExtension(catalogFileName(path)));
    if (executableName.length < 3 || directoryName.length < 3) return false;
    return directoryName.startsWith(executableName) || executableName.startsWith(directoryName);
  });
  if (versionedMatches.length === 1) return versionedMatches[0];
  return '';
}

export function chooseCoverFileName(names: string[]): string {
  for (let index = 0; index < COVER_PRIORITY.length; index++) {
    const expected = COVER_PRIORITY[index];
    const found = names.find((name: string) => name.toLowerCase() === expected);
    if (found) return found;
  }
  return '';
}
