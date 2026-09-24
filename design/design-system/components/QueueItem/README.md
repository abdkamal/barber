# QueueItem

صف في طابور الحلاق. يمرر المستهلك `position` و`name` و`services` و`eta` و`duration` و`status` واختياريًا `kind="requested"` مع `requestedAt`، و`walkIn`، و`action`. يوضع داخل `<ul className="dw-queue">`.

- المستدعى يُحدّ بلون الانتباه.
- الإجراءات على الصف قليلة؛ القرارات (تأجيل / لم يحضر) في ورقة منبثقة عند الضغط.
