# CVirtual Administración

`cvirtual_adm` es la segunda aplicación del sistema. El cliente inicia sesión con correo y contraseña para actualizar únicamente su información, disponibilidad y contraseña. El administrador controla la relación de cuentas, pagos, renovaciones, videos editados y publicación del QR.

## Seguridad de acceso

La aplicación usa **Supabase Auth con correo y contraseña**. No contiene contraseñas fijas, claves `service_role` ni tokens privados. El texto `Admin2026` debe utilizarse solo como contraseña temporal en el panel **Authentication → Users** de Supabase al crear tu usuario administrador; después debes cambiarla desde el panel de cliente o Supabase Auth.

> Para acceder como administrador, primero crea un usuario con tu correo real en Supabase Authentication. Luego ejecuta el bloque final de `003_cvirtual_adm.sql` cambiando `TU_CORREO_ADMIN@EJEMPLO.COM` por ese correo. Eso asigna el rol `admin` de forma segura.

## Orden de SQL

| Orden | Archivo | Finalidad |
|---:|---|---|
| 1 | `001_cv_virtual_schema.sql` | Tablas centrales, QR, pagos y roles. |
| 2 | `002_supabase_storage_media.sql` | Buckets privados para foto y video. |
| 3 | `003_cvirtual_adm.sql` | Acceso de clientes, pagos de servicio, QR y videos editados. |

El archivo `003_cvirtual_adm.sql` se entrega en esta carpeta. Los dos anteriores corresponden al proyecto de registro ya creado.

## Configuración de Supabase Auth

En **Authentication → Providers**, habilita el proveedor **Email**. En **Authentication → URL Configuration**, agrega la dirección donde publicarás esta aplicación en **Redirect URLs**, por ejemplo:

```text
https://cartasinteractivas-jpg.github.io/cvirtual_adm/
```

Cuando un cliente pulse **Activar mi acceso**, debe escribir el mismo correo utilizado al registrar su currículo. Su solicitud aparece para aprobación administrativa antes de que pueda modificar el perfil asociado.

## Precio y renovación

| Servicio | Precio | Efecto |
|---|---:|---|
| Alta inicial | S/ 40 | Registra el servicio y otorga seis meses de vigencia. |
| Renovación | S/ 20 | Extiende la fecha de vencimiento seis meses. |
| Cambio de video | S/ 10 | Registra el servicio; no altera la fecha de vencimiento. |

El administrador registra los servicios pagados desde la ficha del cliente. La web no procesa tarjetas ni Yape automáticamente: conserva el control manual de verificación.

## Flujo de video y QR

El cliente actualiza datos, pero no puede reemplazar el video público. El administrador recibe el material original del registro, lo edita, carga el resultado a `candidate-videos`, lo marca como listo y finalmente publica el perfil. El QR se habilita o deshabilita de forma independiente; un QR deshabilitado devuelve la pantalla de construcción.

## Publicación en GitHub Pages

Esta aplicación es estática. Sube todos los archivos de esta carpeta a la raíz de un repositorio nuevo llamado, por ejemplo, `cvirtual_adm`. En **Settings → Pages**, selecciona **Deploy from a branch**, rama `main` y carpeta `/(root)`.

Antes de publicar, abre `config.js` y confirma la URL y clave `anon` de tu proyecto Supabase. La clave `anon` es pública por diseño y la protección depende de RLS y las funciones SQL incluidas.
