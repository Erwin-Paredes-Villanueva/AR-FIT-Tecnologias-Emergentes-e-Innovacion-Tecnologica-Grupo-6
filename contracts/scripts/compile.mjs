// Compila los contratos con solc-js y reparte los ABI a la app y a las Edge Functions.
//   ARFitTrace  → procedencia del modelo de prenda y trazabilidad de pedidos
//   ARFitUnits  → unidades físicas (serie + código de barras) y su activación
import fs from 'node:fs';
import path from 'node:path';
import solc from 'solc';

const root = path.resolve(import.meta.dirname, '..');
const files = ['ARFitTrace.sol', 'ARFitUnits.sol'];

const input = {
  language: 'Solidity',
  sources: Object.fromEntries(files.map((f) => [f, { content: fs.readFileSync(path.join(root, f), 'utf8') }])),
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    evmVersion: 'paris',
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } },
  },
};

const output = JSON.parse(solc.compile(JSON.stringify(input)));
const errors = (output.errors || []).filter((e) => e.severity === 'error');
for (const e of output.errors || []) console.log(e.formattedMessage);
if (errors.length) process.exit(1);

fs.mkdirSync(path.join(root, 'build'), { recursive: true });
fs.mkdirSync(path.join(root, '../app/assets/blockchain'), { recursive: true });

const abis = {};
for (const name of ['ARFitTrace', 'ARFitUnits']) {
  const c = output.contracts[`${name}.sol`][name];
  const artifact = { abi: c.abi, bytecode: '0x' + c.evm.bytecode.object };
  fs.writeFileSync(path.join(root, `build/${name}.json`), JSON.stringify(artifact, null, 2));
  fs.writeFileSync(path.join(root, `../app/assets/blockchain/${name}.abi.json`), JSON.stringify(c.abi));
  abis[name] = JSON.stringify(c.abi);
  console.log('Compilado OK →', `build/${name}.json`);
}

// ABI para las Edge Functions (Deno)
fs.writeFileSync(
  path.join(root, '../supabase/functions/_shared/abi.ts'),
  `// Generado por contracts/scripts/compile.mjs — no editar a mano\n` +
    `export const ARFIT_ABI = ${abis.ARFitTrace};\n` +
    `export const ARFIT_UNITS_ABI = ${abis.ARFitUnits};\n`,
);
