import { Global, Module } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { LoginThrottle } from './login-throttle';
import { PasswordHasher } from './passwords';
import { PasswordResetService } from './password-reset.service';
import { TokenService } from './tokens';

@Global()
@Module({
  controllers: [AuthController],
  providers: [
    { provide: PasswordHasher, inject: [APP_CONFIG], useFactory: (c: AppConfig) => new PasswordHasher(c.auth.argon2) },
    { provide: TokenService, inject: [APP_CONFIG], useFactory: (c: AppConfig) => new TokenService(c.auth) },
    { provide: LoginThrottle, inject: [APP_CONFIG], useFactory: (c: AppConfig) => new LoginThrottle(c.backoff) },
    AuthService,
    PasswordResetService,
  ],
  exports: [PasswordHasher, TokenService, LoginThrottle, AuthService, PasswordResetService],
})
export class AuthModule {}
