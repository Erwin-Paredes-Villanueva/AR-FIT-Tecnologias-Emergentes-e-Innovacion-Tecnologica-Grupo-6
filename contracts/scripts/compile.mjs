// Compila ARFitTrace.sol con solc-js y reparte el ABI a la app y a las Edge Functions.
import fs from 'node:fs';
import path from 'node:path';
import solc from 'solc';

const root = path.resolve(import.meta.dirname, '..');
const source = fs.readFileSync(path.join(root, 'ARFitTrace.sol'), 'utf8');

const input = {
  language: 'Solidity',
  sources: { 'ARFitTrace.sol': { content: source } },
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

const c = output.contracts['ARFitTrace.sol'].ARFitTrace;
const artifact = { abi: c.abi, bytecode: '0x' + c.evm.bytecode.object };
fs.mkdirSync(path.join(root, 'build'), { recursive: true });
fs.writeFileSync(path.join(root, 'build/ARFitTrace.json'), JSON.stringify(artifact, null, 2));

// ABI para la Edge Function (Deno) y para la app Flutter (lectura directa de la cadena)
const abiJson = JSON.stringify(c.abi);
fs.writeFileSync(
  path.join(root, '../supabase/functions/_shared/abi.ts'),
  `// Generado por contracts/scripts/compile.mjs — no editar a mano\nexport const ARFIT_ABI = ${abiJson};\n`,
);
fs.mkdirSync(path.join(root, '../app/assets/blockchain'), { recursive: true });
fs.writeFileSync(path.join(root, '../app/assets/blockchain/ARFitTrace.abi.json'), abiJson);
console.log('Compilado OK →', 'build/ARFitTrace.json');
