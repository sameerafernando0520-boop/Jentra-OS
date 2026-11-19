import path from 'node:path';

// Relative checks also work when the workspace is a substituted drive root.
export function isReleaseBuildPath(root, target, paths = path) {
  const relative = paths.relative(root, target);
  return !paths.isAbsolute(relative) && relative.startsWith('build' + paths.sep);
}
