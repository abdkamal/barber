import 'package:saloni_api/saloni_api.dart' as api;
import 'package:saloni_ui/saloni_ui.dart' as ui;

/// يحوّل حالة الحجز من نموذج الواجهة البرمجية إلى تعداد عرض «صالوني».
ui.BookingStatus mapBookingStatus(api.BookingStatus status) {
  switch (status) {
    case api.BookingStatus.offered:
      return ui.BookingStatus.offered;
    case api.BookingStatus.waiting:
      return ui.BookingStatus.waiting;
    case api.BookingStatus.called:
      return ui.BookingStatus.called;
    case api.BookingStatus.inService:
      return ui.BookingStatus.inService;
    case api.BookingStatus.done:
      return ui.BookingStatus.done;
    case api.BookingStatus.cancelled:
    case api.BookingStatus.expired:
      return ui.BookingStatus.cancelled;
    case api.BookingStatus.noShow:
      return ui.BookingStatus.noShow;
  }
}

ui.BookingStatus mapPaymentStatus(api.PaymentStatus status) => switch (status) {
      api.PaymentStatus.awaitingConfirmation => ui.BookingStatus.payAwaiting,
      api.PaymentStatus.confirmed => ui.BookingStatus.payConfirmed,
    };
