import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { WhatsappGateway } from './whatsapp.gateway';
import { WhatsappService } from './whatsapp.service';
import { WhatsappController } from './whatsapp.controller';
import { WhatsappSession } from './entities/whatsapp-session.entity';

@Module({
  imports: [TypeOrmModule.forFeature([WhatsappSession])],
  controllers: [WhatsappController],
  providers: [WhatsappService, WhatsappGateway],
  exports: [WhatsappService],
})
export class WhatsappModule {}
