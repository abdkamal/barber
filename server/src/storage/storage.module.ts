import { Module } from '@nestjs/common';
import { ImageStorageService } from './image-storage.service';
import { MediaController } from './media.controller';

@Module({
  controllers: [MediaController],
  providers: [ImageStorageService],
  exports: [ImageStorageService],
})
export class StorageModule {}
