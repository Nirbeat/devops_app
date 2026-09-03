import app from './app.js';
import { env } from './config/env.js';
import { connectDB } from './config/db.js';

async function start() {
  await connectDB();
  app.listen(env.port, () => {
    console.log(`Servidor escuchando en http://localhost:${env.port}`);
  });
}

start().catch((err) => {
  console.error('Error al iniciar el servidor:', err);
  process.exit(1);
});
