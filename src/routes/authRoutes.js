import { Router } from 'express';
import {
  register,
  login,
  profile,
} from '../controllers/authController.js';
import {
  validateUserRegistration,
  validateUserLogin,
  handleValidationErrors,
} from '../middlewares/validate.js';
import { requireAuth } from '../middlewares/auth.js';

const router = Router();

router.post(
  '/register',
  validateUserRegistration,
  handleValidationErrors,
  register
);
router.post('/login', validateUserLogin, handleValidationErrors, login);
router.get('/profile', requireAuth, profile);

export default router;
