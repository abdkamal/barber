import type * as React from 'react';

export type IconName = 'scissors' | 'clock' | 'hourglass-medium' | 'user' | 'users-three' | 'calendar-check' | 'bell-ringing' | 'wifi-slash' | 'wifi-high'
  | 'check' | 'check-circle' | 'x' | 'x-circle' | 'caret-left' | 'caret-right' | 'plus' | 'coins' | 'receipt' | 'chart-bar' | 'gear-six' | 'qr-code'
  | 'phone' | 'lock-simple' | 'eye' | 'eye-slash' | 'warning' | 'info' | 'clock-counter-clockwise' | 'arrow-u-up-left' | 'user-plus' | 'coffee'
  | 'storefront' | 'list-numbers' | 'sign-out' | 'map-pin' | 'whatsapp-logo' | 'instagram-logo' | 'navigation-arrow' | 'image' | 'package' | 'tag';
export interface IconProps { name: IconName; size?: number; label?: string; mirror?: boolean; className?: string }
export declare function Icon(props: IconProps): React.ReactElement;

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger'; size?: 'sm' | 'md' | 'lg'; icon?: IconName; block?: boolean; loading?: boolean }
export declare function Button(props: ButtonProps): React.ReactElement;

export interface TextFieldProps { id?: string; label: string; value?: string; type?: 'text' | 'password' | 'tel' | 'number';
  placeholder?: string; prefix?: string; hint?: string; error?: string; dir?: 'ltr' | 'rtl'; inputMode?: string }
export declare function TextField(props: TextFieldProps): React.ReactElement;

export interface SegmentedControlProps { label: string; options: { value: string; label: string; icon?: IconName }[]; value?: string; onChange?: (v: string) => void }
export declare function SegmentedControl(props: SegmentedControlProps): React.ReactElement;

export interface ServiceChipProps { name: string; minutes: number; price: number | string; currency?: string; selected?: boolean; onToggle?: (on: boolean) => void }
export declare function ServiceChip(props: ServiceChipProps): React.ReactElement;

export type BookingStatus = 'waiting' | 'called' | 'in_service' | 'done' | 'cancelled' | 'no_show' | 'postponed' | 'offered' | 'requested' | 'walk_in'
  | 'pay_awaiting' | 'pay_confirmed';
export interface StatusBadgeProps { status: BookingStatus; size?: 'sm'; label?: string; tone?: 'neutral' | 'primary' | 'steel' | 'success' | 'warning' | 'danger' }
export declare function StatusBadge(props: StatusBadgeProps): React.ReactElement;

export interface AvatarProps { name: string; size?: number; tone?: 'steel' }
export declare function Avatar(props: AvatarProps): React.ReactElement;

export interface BarberOptionProps { name?: string; fastest?: boolean; nextAt?: string; wait?: string; note?: string; selected?: boolean; unavailable?: boolean; reason?: string }
export declare function BarberOption(props: BarberOptionProps): React.ReactElement;

export interface EtaCardProps { eta: string; ampm?: string; status?: BookingStatus; kind?: 'queue' | 'requested'; barber: string; services: string;
  updated?: string; originalEta?: string; reason?: string; live?: boolean; staleFor?: string }
export declare function EtaCard(props: EtaCardProps): React.ReactElement;

export interface QueueItemProps { position: number; name: string; services: string; eta: string; duration?: string; status?: BookingStatus;
  kind?: 'queue' | 'requested'; requestedAt?: string; walkIn?: boolean; action?: React.ReactNode }
export declare function QueueItem(props: QueueItemProps): React.ReactElement;

export interface CurrentServiceCardProps { customer: string; services: string; startedAt: string; elapsed: number; estimate: number; onEnd?: () => void; onEdit?: () => void }
export declare function CurrentServiceCard(props: CurrentServiceCardProps): React.ReactElement;

export interface OfferCardProps { requested: string; offered: string; barber: string; secondsLeft: number; total?: number; onAccept?: () => void; onDecline?: () => void }
export declare function OfferCard(props: OfferCardProps): React.ReactElement;

export interface ImpactListProps { title?: string; note?: string; items: { name: string; from: string; to: string; delta?: number; notify?: boolean; pastClosing?: boolean }[] }
export declare function ImpactList(props: ImpactListProps): React.ReactElement;

export interface BannerProps { tone?: 'info' | 'success' | 'warning' | 'danger'; title?: string; children?: React.ReactNode; action?: React.ReactNode }
export declare function Banner(props: BannerProps): React.ReactElement;

export interface ConnectionBarProps { state: 'online' | 'syncing' | 'offline'; since?: string; pending?: number }
export declare function ConnectionBar(props: ConnectionBarProps): React.ReactElement;

export interface SwitchProps { id?: string; label: string; description?: string; checked?: boolean; onChange?: (on: boolean) => void }
export declare function Switch(props: SwitchProps): React.ReactElement;

export interface StatTileProps { label: string; value: string | number; unit?: string; delta?: string; deltaTone?: 'success' | 'warning' | 'danger'; series?: number[] }
export declare function StatTile(props: StatTileProps): React.ReactElement;

export interface BottomNavProps { items: { icon: IconName; label: string; badge?: number }[]; active?: number }
export declare function BottomNav(props: BottomNavProps): React.ReactElement;

export interface EmptyStateProps { icon?: IconName; title: string; body?: string; action?: React.ReactNode }
export declare function EmptyState(props: EmptyStateProps): React.ReactElement;

export interface CatalogItemProps { kind: 'service' | 'product'; name: string; price: number | string; currency?: string; description?: string;
  features?: string[]; minutes?: number; image?: string }
export declare function CatalogItem(props: CatalogItemProps): React.ReactElement;

export interface HoursListProps { openNow?: boolean; days: { day: string; from?: string; to?: string; closed?: boolean; today?: boolean }[] }
export declare function HoursList(props: HoursListProps): React.ReactElement;

export interface ContactBarProps { address?: string; phone?: string; whatsapp?: string; maps?: boolean; instagram?: string }
export declare function ContactBar(props: ContactBarProps): React.ReactElement;

declare global { interface Window { Saloni: {
  Icon: typeof Icon; Button: typeof Button; TextField: typeof TextField; SegmentedControl: typeof SegmentedControl; ServiceChip: typeof ServiceChip;
  StatusBadge: typeof StatusBadge; Avatar: typeof Avatar; BarberOption: typeof BarberOption; EtaCard: typeof EtaCard; QueueItem: typeof QueueItem;
  CurrentServiceCard: typeof CurrentServiceCard; OfferCard: typeof OfferCard; ImpactList: typeof ImpactList; Banner: typeof Banner;
  ConnectionBar: typeof ConnectionBar; Switch: typeof Switch; StatTile: typeof StatTile; BottomNav: typeof BottomNav; EmptyState: typeof EmptyState;
  CatalogItem: typeof CatalogItem; HoursList: typeof HoursList; ContactBar: typeof ContactBar } } }
