/// Configuración de servicios externos. Se completa con `tools/configure_app.sh`
/// o a mano después de crear el proyecto de Supabase y desplegar el contrato.
class AppConfig {
  // Supabase → Project Settings → API Keys: "publishable key" (o la anon key legacy).
  // Es pública por diseño; la seguridad la dan las políticas RLS.
  static const supabaseUrl = 'https://oyqpoztpifwwfzklfhvt.supabase.co';
  static const supabaseKey = 'sb_publishable_DORXaThSB9UcizU9qrmmHQ_wMRGuR4E';

  // Polygon Amoy (testnet pública, chainId 80002)
  static const amoyRpcUrl = 'https://polygon-amoy-bor-rpc.publicnode.com';
  static const contractAddress = '0x04191b41193a7B7C5e3765949faB43fD0cc7cb71';
  static const explorerUrl = 'https://amoy.polygonscan.com';
}
