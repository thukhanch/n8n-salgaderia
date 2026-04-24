import 'reflect-metadata';
import * as dotenv from 'dotenv';
import * as path from 'path';

dotenv.config({ path: path.resolve(__dirname, '.env') });

import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  app.enableCors({
    origin: true,
    credentials: true,
  });

  app.setGlobalPrefix('api');

  const port = parseInt(process.env.PORT || '3000', 10);
  await app.listen(port);
  console.log(`N8N Salgaderia Baileys bridge running on http://localhost:${port}`);
}

bootstrap();
