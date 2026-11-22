// Despliega ARFitUnits en Polygon Amoy enlazado al ARFitTrace ya desplegado.
// Guarda UNITS_CONTRACT_ADDRESS en contracts/.env y build/units-deployment.json.
import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';
import { ContractFactory, JsonRpcProvider, Wallet, formatEther, parseUnits } from 'ethers';

const root = path.resolve(import.meta.dirname, '..');
const { abi, bytecode } = JSON.parse(fs.readFileSync(path.join(root, 'build/ARFitUnits.json'), 'utf8'));
const trace = process.env.CONTRACT_ADDRESS;
if (!trace) throw new Error('Falta CONTRACT_ADDRESS (ARFitTrace) en contracts/.env');

const provider = new JsonRpcProvider(process.env.AMOY_RPC_URL);
const wallet = new Wallet(process.env.RELAYER_PRIVATE_KEY, provider);
const net = await provider.getNetwork();
if (net.chainId !== 80002n) throw new Error(`Se esperaba Polygon Amoy (80002), RPC devuelve ${net.chainId}`);

const balance = await provider.getBalance(wallet.address);
console.log(`Desplegando ARFitUnits desde ${wallet.address} (saldo ${formatEther(balance)} POL)...`);
if (balance === 0n) throw new Error('La wallet no tiene POL. Usa el faucet de Amoy primero.');

const factory = new ContractFactory(abi, bytecode, wallet);
const tip = parseUnits(process.env.GAS_PRIORITY_GWEI ?? '30', 'gwei');
const contract = await factory.deploy(trace, { maxPriorityFeePerGas: tip, maxFeePerGas: tip + parseUnits('5', 'gwei') });
const tx = contract.deploymentTransaction();
console.log('Tx:', `https://amoy.polygonscan.com/tx/${tx.hash}`);
await contract.waitForDeployment();
const address = await contract.getAddress();
console.log('ARFitUnits desplegado en:', `https://amoy.polygonscan.com/address/${address}`);

const envPath = path.join(root, '.env');
let env = fs.readFileSync(envPath, 'utf8');
env = /^UNITS_CONTRACT_ADDRESS=/m.test(env)
  ? env.replace(/^UNITS_CONTRACT_ADDRESS=.*$/m, `UNITS_CONTRACT_ADDRESS=${address}`)
  : `${env.trimEnd()}\nUNITS_CONTRACT_ADDRESS=${address}\n`;
fs.writeFileSync(envPath, env, { mode: 0o600 });
fs.writeFileSync(
  path.join(root, 'build/units-deployment.json'),
  JSON.stringify(
    { network: 'polygon-amoy', chainId: 80002, address, trace, issuer: wallet.address, txHash: tx.hash, deployedAt: new Date().toISOString() },
    null,
    2,
  ),
);
console.log('Dirección guardada en contracts/.env y build/units-deployment.json');
