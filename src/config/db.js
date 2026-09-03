import mongoose from 'mongoose';
import { env } from './env.js';

export async function connectDB(uri = env.mongoUri) {
  const conn = await mongoose.connect(uri);
  console.log(`MongoDB conectado: ${conn.connection.host}`);
  return conn;
}

export async function disconnectDB() {
  await mongoose.disconnect();
}
