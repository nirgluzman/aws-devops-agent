const { build } = require('esbuild');

build({
  entryPoints: ['./src/index.ts'],
  bundle: true,
  platform: 'node',
  logLevel: 'info',
  outfile: './dist/index.js',

  // Bundle everything, including AWS SDK v3.
  // The Lambda runtime ships a built-in SDK, but it's often outdated and missing security patches.
  // Bundling gives us: pinned SDK version, ~1.7x faster cold starts, and tree-shaken bundle size.
  // Ref: https://aws.amazon.com/blogs/compute/optimizing-node-js-dependencies-in-aws-lambda/
  external: [],

  minify: true,
  target: 'node24',
}).catch(() => process.exit(1));
