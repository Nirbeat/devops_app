import { describe, it } from 'mocha';
import { expect } from 'chai';
import request from 'supertest';
import app from '../../src/app.js';

describe('Endpoint de salud GET /health', () => {
  it('debe devolver 200 y un status "ok"', async () => {
    const res = await request(app).get('/health');
    expect(res.status).to.equal(200);
    expect(res.body.status).to.equal('ok');
  });

  it('debe incluir un campo uptime numérico', async () => {
    const res = await request(app).get('/health');
    expect(res.body).to.have.property('uptime');
    expect(res.body.uptime).to.be.a('number');
    expect(res.body.uptime).to.be.greaterThan(0);
  });
});
