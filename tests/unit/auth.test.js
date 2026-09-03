import { describe, it } from 'mocha';
import { expect } from 'chai';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { env } from '../../src/config/env.js';

describe('Hash de contraseña (bcrypt)', () => {
  it('debe hashear una contraseña y poder compararla', async () => {
    const password = 'secret123';
    const hash = await bcrypt.hash(password, 12);
    expect(hash).to.not.equal(password);
    const ok = await bcrypt.compare(password, hash);
    expect(ok).to.be.true;
  });

  it('debe rechazar una contraseña incorrecta', async () => {
    const hash = await bcrypt.hash('secret123', 12);
    const ok = await bcrypt.compare('wrongpass', hash);
    expect(ok).to.be.false;
  });

  it('debe generar hashes distintos para la misma contraseña (sal)', async () => {
    const h1 = await bcrypt.hash('secret123', 12);
    const h2 = await bcrypt.hash('secret123', 12);
    expect(h1).to.not.equal(h2);
  });
});

describe('Generación y verificación de token JWT', () => {
  const payload = { id: 'abc123', email: 'u@example.com' };

  it('debe firmar un token con el payload y verificar correctamente', () => {
    const token = jwt.sign(payload, env.jwtSecret, { expiresIn: env.jwtExpiresIn });
    const decoded = jwt.verify(token, env.jwtSecret);
    expect(decoded.id).to.equal('abc123');
    expect(decoded.email).to.equal('u@example.com');
  });

  it('debe lanzar error al verificar un token con secreto distinto', () => {
    const token = jwt.sign(payload, 'secreto-diferente');
    expect(() => jwt.verify(token, env.jwtSecret)).to.throw();
  });
});
