import { Module } from '@nestjs/common';
import { StorageModule } from '../storage/storage.module';
import { PhotosController } from './photos.controller';
import { ProfileController } from './profile.controller';

@Module({
  imports: [StorageModule],
  controllers: [ProfileController, PhotosController],
})
export class ProfileModule {}
