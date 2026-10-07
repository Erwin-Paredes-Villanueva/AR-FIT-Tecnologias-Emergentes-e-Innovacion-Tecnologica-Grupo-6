import 'dotenv/config';
import { JsonRpcProvider, Wallet, formatEther } from 'ethers';

const provider = new JsonRpcProvider(process.env.AMOY_RPC_URL);
const wallet = new Wallet(process.env.RELAYER_PRIVATE_KEY, provider);
const [bal, net] = await Promise.all([provider.getBalance(wallet.address), provider.getNetwork()]);
console.log(`Red: chainId ${net.chainId}`);
console.log(`${wallet.address}: ${formatEther(bal)} POL`);
