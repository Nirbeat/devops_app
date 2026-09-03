import jwt from 'jsonwebtoken';
import { User } from '../models/User.js';
import { env } from '../config/env.js';

function signToken(payload) {
  return jwt.sign(payload, env.jwtSecret, { expiresIn: env.jwtExpiresIn });
}

export async function register(req, res, next) {
  try {
    const { email, password } = req.body;

    const existing = await User.findOne({ email });
    if (existing) {
      return res.status(409).json({ message: 'El email ya está registrado' });
    }

    const user = await User.create({ email, password });
    return res.status(201).json({ message: 'Usuario creado', user: user.toSafeJSON() });
  } catch (error) {
    if (error.code === 11000) {
      return res.status(409).json({ message: 'El email ya está registrado' });
    }
    return next(error);
  }
}

export async function login(req, res, next) {
  try {
    const { email, password } = req.body;

    const user = await User.findOne({ email }).select('+password');
    if (!user || !(await user.comparePassword(password))) {
      return res.status(401).json({ message: 'Credenciales inválidas' });
    }

    const token = signToken({ id: user._id, email: user.email });
    return res.json({ token, user: user.toSafeJSON() });
  } catch (error) {
    return next(error);
  }
}

export async function profile(req, res) {
  const user = await User.findById(req.user.id);
  if (!user) {
    return res.status(404).json({ message: 'Usuario no encontrado' });
  }
  return res.json({ user: user.toSafeJSON() });
}
