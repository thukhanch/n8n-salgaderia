import { Controller, Get, Post, Delete, Param, Body } from '@nestjs/common';
import { WhatsappService } from './whatsapp.service';

@Controller('whatsapp')
export class WhatsappController {
  constructor(private readonly whatsappService: WhatsappService) {}

  @Get('sessions')
  getSessions() {
    return this.whatsappService.getSessions();
  }

  @Get('sessions/:id')
  getSession(@Param('id') id: string) {
    return this.whatsappService.getSession(id);
  }

  @Post('sessions')
  createSession(@Body() body: { name: string }) {
    return this.whatsappService.createSession(body.name);
  }

  @Post('sessions/:id/send')
  sendMessage(
    @Param('id') sessionId: string,
    @Body() body: { to: string; text: string },
  ) {
    return this.whatsappService.sendMessage(sessionId, body.to, body.text);
  }

  @Delete('sessions/:id')
  deleteSession(@Param('id') id: string) {
    return this.whatsappService.deleteSession(id);
  }
}
