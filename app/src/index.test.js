'use strict';

const request = require('supertest');
const app = require('../src/index');

describe('Application Routes', () => {
  describe('GET /', () => {
    it('should return 200 with app info', async () => {
      const res = await request(app).get('/');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('message');
      expect(res.body).toHaveProperty('version');
      expect(res.body).toHaveProperty('hostname');
      expect(res.body.message).toContain('Hello');
    });
  });

  describe('GET /health', () => {
    it('should return 200 healthy status', async () => {
      const res = await request(app).get('/health');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('healthy');
    });
  });

  describe('GET /ready', () => {
    it('should return 200 ready status', async () => {
      const res = await request(app).get('/ready');
      expect(res.status).toBe(200);
      expect(res.body.status).toBe('ready');
    });
  });

  describe('GET /metrics', () => {
    it('should return app metrics', async () => {
      const res = await request(app).get('/metrics');
      expect(res.status).toBe(200);
      expect(res.body).toHaveProperty('uptime_seconds');
      expect(res.body).toHaveProperty('memory_usage_mb');
    });
  });

  describe('404 handler', () => {
    it('should return 404 for unknown routes', async () => {
      const res = await request(app).get('/nonexistent-path');
      expect(res.status).toBe(404);
      expect(res.body).toHaveProperty('error');
    });
  });
});
