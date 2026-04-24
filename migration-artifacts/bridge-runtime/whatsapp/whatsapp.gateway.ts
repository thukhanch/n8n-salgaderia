import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
  OnGatewayConnection,
  OnGatewayDisconnect,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { WhatsappService } from './whatsapp.service';

@WebSocketGateway({
  cors: { origin: 'http://localhost:5173', credentials: true },
  namespace: '/ws',
})
export class WhatsappGateway implements OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(WhatsappGateway.name);

  constructor(
    private whatsappService: WhatsappService,
  ) {}

  handleConnection(client: Socket) {
    console.log(`Client connected: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    console.log(`Client disconnected: ${client.id}`);
  }

  @SubscribeMessage('session:connect')
  async handleConnect(
    @MessageBody() data: { sessionId: string },
    @ConnectedSocket() client: Socket,
  ) {
    await this.whatsappService.connectSession(data.sessionId, (event, payload) => {
      this.server.emit(`session:${event}`, payload);
    });
    return { status: 'connecting' };
  }

  @SubscribeMessage('session:disconnect')
  async handleDisconnect2(@MessageBody() data: { sessionId: string }) {
    await this.whatsappService.disconnectSession(data.sessionId);
    return { status: 'disconnected' };
  }

  @SubscribeMessage('message:send')
  async handleSendMessage(
    @MessageBody() data: { sessionId: string; to: string; text: string },
  ) {
    return this.whatsappService.sendMessage(data.sessionId, data.to, data.text);
  }
}
