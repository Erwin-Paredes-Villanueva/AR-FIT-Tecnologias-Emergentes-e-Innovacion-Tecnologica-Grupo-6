# AR-FIT · Marketplace phygital de moda

**Curso:** Tecnologías Emergentes e Innovación Tecnológica · **Grupo 6**
**Integrantes:** Erwin Paredes Villanueva · Alberto Anampa Antayhua

Aplicación Android (Flutter) de un marketplace de moda que integra tres tecnologías emergentes:

| Tecnología | Uso en AR-FIT | Dónde está |
|---|---|---|
| **Inteligencia artificial** | Recomendador híbrido (contenido + colaborativo + popularidad + ajuste de talla), análisis del perfil de estilo, recomendación de talla por medidas y asistente de compra conversacional (Google Gemini) | `supabase/functions/_shared/recommender.ts`, `supabase/functions/assistant`, `app/lib/core/sizing.dart` |
| **Blockchain** | Contrato `ARFitTrace` en **Polygon Amoy (red pública real)**: registro de procedencia y huella de cada prenda, verificación por administrador, y trazabilidad inmutable de cada pedido (pagado → preparado → recogido → en tránsito → entregado → recibido) | `contracts/ARFitTrace.sol`, `supabase/functions/_shared/chain.ts`, `app/lib/core/chain_reader.dart` |
| **Realidad aumentada** | Probador virtual 2D: la cámara detecta 33 puntos del cuerpo (ML Kit Pose) y deforma la prenda al tamaño real de la talla elegida. Probador 3D en vivo con **Snap Camera Kit**: lentes de Lens Studio con la prenda sobre el cuerpo completo | `app/lib/features/tryon/`, `app/android/.../MainActivity.kt`, `lenses/` |

## Arquitectura

```
App Flutter (APK) ──► Supabase (Auth · Postgres + RLS · Storage · Realtime)
     │                      │
     │                      └─► Edge Functions (Deno)
     │                             ├─ recommend     → motor de recomendación
     │                             ├─ assistant     → Google Gemini
     │                             ├─ checkout      → pedidos + pago simulado
     │                             ├─ order-event   → eventos de envío por rol
     │                             └─ chain-product → registro/verificación de prendas
     │                                     │ firma con la wallet relayer
     │                                     ▼
     └──── lectura directa (eth_call) ──► Polygon Amoy · contrato ARFitTrace
```

- Los usuarios **no necesitan wallet**: las Edge Functions firman las transacciones con una wallet "relayer" del marketplace. En la cadena solo se guardan identificadores hasheados (keccak256 del UUID), nunca datos personales.
- La app **verifica sin confiar en el backend**: lee el contrato directamente desde el RPC público de Polygon y compara la huella sha256 de la ficha mostrada con la registrada on-chain.
- **Phygital**: cada prenda física lleva una etiqueta QR (`arfit://product/<id>`). Cualquiera puede escanearla desde la pestaña *Verificar*.

### Roles

| Rol | Puede |
|---|---|
| Comprador | Registrar medidas y estilo, ver recomendaciones, probarse prendas en RA, chatear con el asistente, comprar y confirmar la recepción |
| Proveedor | Publicar prendas (con quitado automático de fondo para RA), registrarlas en blockchain, preparar pedidos y asignar transportista |
| Transportista | Registrar recojo, puntos de control en tránsito y entrega (cada uno es una transacción) |
| Administrador | Verificar proveedores y firmar la verificación de prendas en blockchain. Se asigna solo desde la base de datos |

## Estructura

```
contracts/         Smart contract Solidity + scripts de compilación/despliegue (ethers + solc)
supabase/          Migración SQL (tablas, RLS, storage) y Edge Functions
tools/garments/    Generador de las ilustraciones PNG del catálogo demo
tools/seed/        Carga del catálogo demo, cuentas demo y registro on-chain
lenses/            Proyectos de Lens Studio 5.22 (un lente 3D por prenda)
app/               Aplicación Flutter
```

## Puesta en marcha

### 1. Blockchain (Polygon Amoy)
```bash
cd contracts && npm install
npm run wallet      # crea la wallet relayer en contracts/.env y muestra su dirección
```
Carga POL de prueba a esa dirección desde un faucet de Amoy (p. ej. https://faucet.polygon.technology) y luego:
```bash
npm run balance
npm run deploy      # compila y despliega ARFitTrace; guarda la dirección en contracts/.env
```

### 2. Supabase (plan gratuito)
1. Crea un proyecto en https://supabase.com.
2. *SQL Editor* → pega y ejecuta `supabase/migrations/20260927000000_init.sql`.
3. (Recomendado para la demo) *Authentication → Sign In / Providers → Email*: desactiva **Confirm email**.
4. Obtén una API key gratuita de Gemini en https://aistudio.google.com/apikey.
5. Despliega las funciones y sus secretos:
```bash
supabase login
supabase link --project-ref <ref-del-proyecto>
cp supabase/.env.example supabase/.env   # completa GEMINI_API_KEY; el resto sale de contracts/.env
supabase secrets set --env-file supabase/.env
supabase functions deploy
```

### 3. Catálogo demo
```bash
cd tools && npm install
cp .env.example .env    # SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY (Project Settings → API)
npm run seed            # cuentas demo → tools/demo-accounts.local.json
```

### 4. Probador 3D (opcional, Snap Camera Kit)
1. Abre cada proyecto de `lenses/` en **Lens Studio 5.22** (la versión máxima compatible con Camera Kit 1.50) y publícalo desde *My Lenses → Publish* como borrador solo para Camera Kit.
2. En https://my-lenses.snapchat.com → *Camera Kit → Lens Scheduler*: agrega la carpeta de lentes como *Lens Source* y crea un *Lens Group* con los lentes.
3. Copia `app/android/camerakit.properties.example` como `app/android/camerakit.properties` y completa el token de Camera Kit y el ID del grupo.
4. Guarda el ID de cada lente en `products.tryon_lens_id`. Sin este archivo la app funciona igual y solo muestra el probador 2D.

### 5. App
Completa `app/lib/config.dart` (URL y anon key de Supabase, dirección del contrato) y compila:
```bash
cd app && flutter build apk --release --target-platform android-arm64
# APK: app/build/app/outputs/flutter-apk/app-release.apk
```

## Cómo funciona el probador RA

La prenda no es una imagen pegada: es una **malla deformable "riggeada" al esqueleto**, como en la animación 2D por huesos.

1. **Detección**: ML Kit Pose encuentra 33 puntos del cuerpo en cada cuadro de la cámara.
2. **Suavizado**: cada punto pasa por un filtro *One Euro*, que elimina el temblor cuando la persona está quieta y casi no añade retraso cuando se mueve. Si un punto se pierde un instante, se conserva su última posición 0,4 s.
3. **Rig de la prenda** (`products.tryon_rig`): costuras de hombro o cintura, bordes del torso y contorno de cada manga o pierna, generados con la ilustración (`tools/garments/generate.py`).
4. **Malla** (`app/lib/features/tryon/rig_fitter.dart`):
   - *Torso*: cuadrícula de 20 × 10 celdas interpolada entre la línea de hombros y la de caderas (se inclina, se tuerce y se angosta al girar). En vestidos continúa siguiendo las piernas.
   - *Mangas y piernas*: tiras que nacen en la sisa o la entrepierna y se montan sobre el eje hombro→codo→muñeca o cadera→rodilla→tobillo, así que se levantan y doblan con el cuerpo.
   - *Escala real*: el ancho sale del contorno de la talla y el largo del largo de la prenda, combinados con las medidas del usuario. Una talla mayor se ve más ancha y más larga sobre el mismo cuerpo.
5. **Frente/espalda**: si la persona se voltea (se invierte el orden de los hombros y deja de verse la cara), se muestra la vista trasera de la prenda (`products.tryon_back_url`).

Las fotos que suben los proveedores no traen rig: se les quita el fondo y se deforman como una sola pieza con el torso.

**Límites del 2D**: no hay simulación de tela ni oclusión; para eso está el probador 3D con Snap Camera Kit (Body Mesh, oclusor de cabeza y simulación de tela en el vestido). Funciona mejor a ~2 m, con buena luz y el cuerpo completo en cuadro.

**Pruebas visuales**: `RIG_OUT=/tmp flutter test test/rig_render_test.dart` dibuja todas las prendas sobre esqueletos sintéticos en 8 poses. En el dispositivo, `flutter build apk --dart-define=ARFIT_TEST_IMAGE=synthetic` (o la ruta de una foto) reemplaza la cámara por un esqueleto o una foto fija.
