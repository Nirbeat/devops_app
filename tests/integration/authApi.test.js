import { describe, it, before, after } from 'mocha';
import { expect } from 'chai';
import request from 'supertest';
import app from '../../src/app.js';
import { connectDB, disconnectDB } from '../../src/config/db.js';
import { User } from '../../src/models/User.js';

const TEST_URI = process.env.MONGO_URI_TEST;

describe('API de autenticación (integración)', function () {
  this.timeout(20000);

  let token;
  let registeredEmail;

  before(async () => {
    if (!TEST_URI) {
      throw new Error('MONGO_URI_TEST no definido');
    }
    await connectDB(TEST_URI);
    await User.deleteMany({});
  });

  after(async () => {
    await User.deleteMany({});
    await disconnectDB();
  });

  describe('POST /api/auth/register', () => {
    it('debe registrar un usuario y devolver 201', async () => {
      const res = await request(app).post('/api/auth/register').send({
        email: 'nuevo@example.com',
        password: 'password123',
      });
      registeredEmail = 'nuevo@example.com';
      expect(res.status).to.equal(201);
      expect(res.body.message).to.equal('Usuario creado');
      expect(res.body.user.email).to.equal('nuevo@example.com');
    });

    it('debe devolver 409 si el email ya existe', async () => {
      const res = await request(app).post('/api/auth/register').send({
        email: 'nuevo@example.com',
        password: 'password123',
      });
      expect(res.status).to.equal(409);
    });

    it('debe devolver 400 si los datos son inválidos', async () => {
      const res = await request(app).post('/api/auth/register').send({
        email: 'email-invalido',
        password: '123',
      });
      expect(res.status).to.equal(400);
      expect(res.body.errors).to.be.an('array');
    });
  });

  describe('POST /api/auth/login', () => {
    it('debe devolver 200 con token para credenciales válidas', async () => {
      const res = await request(app).post('/api/auth/login').send({
        email: registeredEmail,
        password: 'password123',
      });
      expect(res.status).to.equal(200);
      expect(res.body.token).to.be.a('string');
      token = res.body.token;
    });

    it('debe devolver 401 con contraseña incorrecta', async () => {
      const res = await request(app).post('/api/auth/login').send({
        email: registeredEmail,
        password: 'password-incorrecta',
      });
      expect(res.status).to.equal(401);
    });

    it('debe devolver 401 si el email no existe', async () => {
      const res = await request(app).post('/api/auth/login').send({
        email: 'noexiste@example.com',
        password: 'password123',
      });
      expect(res.status).to.equal(401);
    });
  });

  describe('GET /api/auth/profile', () => {
    it('debe devolver 401 sin token', async () => {
      const res = await request(app).get('/api/auth/profile');
      expect(res.status).to.equal(401);
    });

    it('debe devolver 200 con token válido', async () => {
      const res = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', `Bearer ${token}`);
      expect(res.status).to.equal(200);
      expect(res.body.user.email).to.equal(registeredEmail);
    });

    it('debe devolver 401 con token inválido', async () => {
      const res = await request(app)
        .get('/api/auth/profile')
        .set('Authorization', 'Bearer token-invalido');
      expect(res.status).to.equal(401);
    });
  });
});
