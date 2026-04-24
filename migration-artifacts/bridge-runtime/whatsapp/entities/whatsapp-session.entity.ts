import { Entity, Column, PrimaryGeneratedColumn, CreateDateColumn, UpdateDateColumn } from 'typeorm';

export enum SessionStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  QR_WAITING = 'qr_waiting',
  CONNECTED = 'connected',
}

@Entity('whatsapp_sessions')
export class WhatsappSession {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true })
  name: string;

  @Column({
    type: 'enum',
    enum: SessionStatus,
    default: SessionStatus.DISCONNECTED,
  })
  status: SessionStatus;

  @Column({ nullable: true })
  phoneNumber: string;

  @Column({ nullable: true, type: 'text' })
  qrCode: string;

  @CreateDateColumn()
  createdAt: Date;

  @UpdateDateColumn()
  updatedAt: Date;
}
