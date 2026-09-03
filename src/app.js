import express from 'express';
import authRoutes from './routes/authRoutes.js';

const app = express();

app.use(express.json());

app.use('/api/auth', authRoutes);

// Este endpoint está comentado para ser re-integrado en un commit
// app.get('/health', (req, res) => {
//   res.json({ status: 'ok', uptime: process.uptime() });
// });

app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ message: 'Error interno del servidor' });
});

export default app;
