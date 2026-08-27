# CVirtual Administración

`cvirtual_adm` es la segunda aplicación del sistema. El cliente inicia sesión con su **DNI de 8 dígitos** y la clave temporal recibida al registrarse; al entrar puede cambiarla. El administrador usa correo y contraseña. Ambos flujos controlan perfiles, pagos, renovaciones, videos editados y disponibilidad del QR según sus permisos.

## Seguridad de acceso

La aplicación usa **Supabase Auth con correo y contraseña**. No contiene contraseñas fijas, claves `service_role` ni tokens privados. La cuenta administrativa inicial se gestiona desde **Authentication → Users** y su contraseña temporal debe cambiarse desde el panel o Supabase Auth; no debe anotarse en el repositorio.

> Para acceder como administrador, primero crea un usuario con tu correo real en Supabase Authentication. Luego ejecuta el bloque final de `003_cvirtual_adm.sql` cambiando `TU_CORREO_ADMIN@EJEMPLO.COM` por ese correo. Eso asigna el rol `admin` de forma segura.

## Orden de SQL

| Orden | Archivo | Finalidad |
|---:|---|---|
| 1 | `001_cv_virtual_schema.sql` | Tablas centrales, QR, pagos y roles. |
| 2 | `002_supabase_storage_media.sql` | Buckets privados para foto y video. |
| 3 | `003_cvirtual_adm.sql` | Acceso de clientes, pagos de servicio, QR y videos editados. |
| 4 | [`005_dynamic_profiles.sql`](https://github.com/cartasinteractivas-jpg/cv/blob/main/supabase/005_dynamic_profiles.sql) | Perfiles temáticos, módulos, catálogo y destino QR hacia `cv`. |
| 5 | [`006_store_plan.sql`](https://github.com/cartasinteractivas-jpg/cv/blob/main/supabase/006_store_plan.sql) | Plan de tienda, límite técnico de 10 productos y tarifas. |
| 6 | [`007_store_product_images.sql`](https://github.com/cartasinteractivas-jpg/cv/blob/main/supabase/007_store_product_images.sql) | Bucket público de imágenes de producto con escritura limitada al equipo. |
| 7 | [`008_single_screen_content.sql`](https://github.com/cartasinteractivas-jpg/cv/blob/main/supabase/008_single_screen_content.sql) | Servicios, enlaces de YouTube y opiniones verificables para la vista móvil de pantalla única. |
| 8 | [`009_navigation_and_interactions.sql`](https://github.com/cartasinteractivas-jpg/cv/blob/main/supabase/009_navigation_and_interactions.sql) | Veinte navegaciones, agenda de disponibilidad y rutas/cupos. |
| 9 | [`010_presentation_audio.sql`](https://github.com/cartasinteractivas-jpg/cv/blob/main/supabase/010_presentation_audio.sql) | Audio de presentación configurado por el titular con enlace YouTube autorizado. |

El archivo `003_cvirtual_adm.sql` se entrega en esta carpeta. Los dos anteriores corresponden al proyecto de registro ya creado.

## Configuración de Supabase Auth

En **Authentication → Providers**, habilita el proveedor **Email**. En **Authentication → URL Configuration**, agrega la dirección donde publicarás esta aplicación en **Redirect URLs**, por ejemplo:

```text
https://cartasinteractivas-jpg.github.io/cvirtual_adm/
```

El nuevo registro público entrega el DNI como usuario y una clave temporal aleatoria visible una sola vez. El cliente debe guardarla, entrar y cambiarla. Para perfiles anteriores sin DNI, el administrador puede mantener el vínculo por correo mediante la tabla de solicitudes incluida en `003_cvirtual_adm.sql`.

## Precio y renovación

| Servicio | Precio | Efecto |
|---|---:|---|
| Alta inicial | S/ 40 | Registra el servicio y otorga seis meses de vigencia. |
| Renovación | S/ 20 | Extiende la fecha de vencimiento seis meses. |
| Cambio de video | S/ 10 | Registra el servicio; no altera la fecha de vencimiento. |
| Tienda virtual: creación | S/ 60 | Activa el catálogo de hasta 10 productos y extiende la vigencia seis meses. |
| Tienda virtual: mantenimiento | S/ 30 | Conserva el plan comercial y extiende la vigencia seis meses. |

El administrador registra los servicios pagados desde la ficha del cliente. La web no procesa tarjetas ni Yape automáticamente: conserva el control manual de verificación.

## Tienda virtual y catálogo

Desde **Tema y módulos**, el administrador activa la modalidad **Tienda virtual**. Luego, desde **Gestionar catálogo** en la ficha del perfil, carga una imagen clara, nombre, precio, categoría y descripción por cada artículo. El sistema bloquea el artículo número 11: el máximo es de **10 productos por tienda**. Las imágenes de catálogo se almacenan en Supabase Storage en el bucket público `store-product-images`; solo los roles administrativos pueden agregar o eliminar esos archivos.

## Flujo de video y QR

El cliente actualiza datos, pero no puede reemplazar el video público. El administrador recibe el material original del registro, lo edita, carga el resultado a `candidate-videos`, lo marca como listo y finalmente publica el perfil. El QR se habilita o deshabilita de forma independiente; un QR deshabilitado devuelve la pantalla de construcción.

## Contenido en pantalla única

Desde **Gestionar → Contenido y videos**, el equipo puede añadir servicios, trabajos realizados y enlaces HTTPS de YouTube. En **Tema y módulos** se activan los botones que verá el visitante sobre el video de fondo. El panel también permite guardar opiniones, pero exige un enlace de evidencia y una confirmación explícita de autorización; no se crean reseñas ni valoraciones de muestra.

Después de ejecutar la migración 009, **Tema y módulos** ofrece 20 estilos de navegación para el QR y **Agenda y rutas** permite al personal indicar horarios libres del mes o cupos de transporte. Después de la migración 010, cada cliente configura desde **Editar mis datos → Audio de mi presentación** el enlace de YouTube autorizado que acompañará su video público.

## Publicación en GitHub Pages

Esta aplicación es estática. Sube todos los archivos de esta carpeta a la raíz de un repositorio nuevo llamado, por ejemplo, `cvirtual_adm`. En **Settings → Pages**, selecciona **Deploy from a branch**, rama `main` y carpeta `/(root)`.

Antes de publicar, abre `config.js` y confirma la URL y clave `anon` de tu proyecto Supabase. La clave `anon` es pública por diseño y la protección depende de RLS y las funciones SQL incluidas.
