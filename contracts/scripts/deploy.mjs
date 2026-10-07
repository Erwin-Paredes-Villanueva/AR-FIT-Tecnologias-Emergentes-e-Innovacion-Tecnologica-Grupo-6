// Despliega ARFitTrace en Polygon Amoy y guarda la dirección en .env y en la app.
import 'dotenv/config';
import fs from 'node:fs';
import path from 'node:path';
import { ContractFactory, JsonRpcProvider, Wallet, formatEther, parseUnits } from 'ethers';

const root = path.resolve(import.meta.dirname, '..');
const { abi, bytecode } = JSON.parse(fs.readFileSync(path.join(root, 'build/ARFitTrace.json'), 'utf8'));

const provider = new JsonRpcProvider(process.env.AMOY_RPC_URL);
const wallet = new Wallet(process.env.RELAYER_PRIVATE_KEY, provider);
const net = await provider.getNetwork();
if (net.chainId !== 80002n) throw new Error(`Se esperaba Polygon Amoy (80002), RPC devuelve ${net.chainId}`);

const balance = await provider.getBalance(wallet.address);
console.log(`Desplegando desde ${wallet.address} (saldo ${formatEther(balance)} POL)...`);
if (balance === 0n) throw new Error('La wallet no tiene POL. Usa el faucet de Amoy primero.');

const factory = new ContractFactory(abi, bytecode, wallet);
// Amoy tiene comisión base ~0: basta la propina mínima de Polygon (~25 gwei)
const tip = parseUnits(process.env.GAS_PRIORITY_GWEI ?? '30', 'gwei');
const contract = await factory.deploy({ maxPriorityFeePerGas: tip, maxFeePerGas: tip + parseUnits('5', 'gwei') });
const tx = contract.deploymentTransaction();
console.log('Tx:', `https://amoy.polygonscan.com/tx/${tx.hash}`);
await contract.waitForDeployment();
const address = await contract.getAddress();
console.log('Contrato desplegado en:', `https://amoy.polygonscan.com/address/${address}`);

const envPath = path.join(root, '.env');
const env = fs.readFileSync(envPath, 'utf8').replace(/^CONTRACT_ADDRESS=.*$/m, `CONTRACT_ADDRESS=${address}`);
fs.writeFileSync(envPath, env, { mode: 0o600 });
fs.writeFileSync(
  path.join(root, 'build/deployment.json'),
  JSON.stringify({ network: 'polygon-amoy', chainId: 80002, address, txHash: tx.hash, deployedAt: new Date().toISOString() }, null, 2),
);
console.log('Dirección guardada en contracts/.env y build/deployment.json');
