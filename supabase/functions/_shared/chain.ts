// Conexión con el contrato ARFitTrace desplegado en Polygon Amoy (testnet pública real).
import { Contract, JsonRpcProvider, Wallet, keccak256, parseUnits, toUtf8Bytes, sha256 } from 'npm:ethers@6';
import { ARFIT_ABI } from './abi.ts';

export const EXPLORER = 'https://amoy.polygonscan.com';

// Debe coincidir con el enum Status del contrato
export const STATUS_CODE: Record<string, number> = {
  created: 0,
  prepared: 1,
  picked_up: 2,
  in_transit: 3,
  delivered: 4,
  received: 5,
  cancelled: 6,
};

let _contract: Contract | null = null;

export function contract(): Contract {
  if (_contract) return _contract;
  const rpc = Deno.env.get('AMOY_RPC_URL') ?? 'https://polygon-amoy-bor-rpc.publicnode.com';
  const provider = new JsonRpcProvider(rpc, 80002, { staticNetwork: true });
  const wallet = new Wallet(Deno.env.get('RELAYER_PRIVATE_KEY')!, provider);
  _contract = new Contract(Deno.env.get('CONTRACT_ADDRESS')!, ARFIT_ABI, wallet);
  return _contract;
}

/** UUID de Supabase → bytes32 on-chain (no expone el UUID ni datos personales). */
export const ref = (uuid: string) => keccak256(toUtf8Bytes(uuid));

/** Huella de la ficha de la prenda. La app recalcula exactamente la misma cadena. */
export function productDataHash(p: {
  id: string; supplier_id: string; name: string; brand: string;
  category: string; color: string; origin: string; materials: string;
}): string {
  const canonical = [p.id, p.supplier_id, p.name, p.brand, p.category, p.color, p.origin, p.materials].join('|');
  return sha256(toUtf8Bytes(canonical));
}

/**
 * Envía una transacción y espera 1 confirmación. Reintenta si otra petición
 * concurrente usó el mismo nonce del relayer.
 */
export async function sendTx(
  method: string,
  args: unknown[],
): Promise<{ hash: string; blockNumber: number }> {
  const c = contract();
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      // Amoy: comisión base ~0, se paga solo la propina mínima de Polygon
      const tip = parseUnits(Deno.env.get('GAS_PRIORITY_GWEI') ?? '30', 'gwei');
      const tx = await c.getFunction(method).send(...args, {
        maxPriorityFeePerGas: tip,
        maxFeePerGas: tip + parseUnits('5', 'gwei'),
      });
      const receipt = await tx.wait(1, 90_000);
      if (!receipt || receipt.status !== 1) throw new Error(`La transacción ${tx.hash} falló`);
      return { hash: tx.hash, blockNumber: receipt.blockNumber };
    } catch (e) {
      const msg = String((e as Error)?.message ?? e);
      const retriable = /nonce|replacement|already known/i.test(msg);
      if (!retriable || attempt === 2) throw e;
      await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
    }
  }
  throw new Error('unreachable');
}
