# StatusBadge

شارة حالة الحجز أو الدفع. يمرر المستهلك `status` واختياريًا `size="sm"` و`label` و`tone`.

| status | النص | اللون |
|---|---|---|
| waiting | بانتظار الدور | neutral |
| called | اقترب دورك | warning |
| in_service | في الخدمة | primary |
| done | تمت الخدمة | success |
| cancelled / no_show | ملغى / لم يحضر | danger |
| postponed | مؤجَّل دورًا | warning |
| offered / requested | عرض مؤقت / ساعة محددة | steel |
| walk_in | حاضر | neutral |
| pay_awaiting / pay_confirmed | بانتظار تأكيد الدفع / تم تأكيد الدفع | warning / success |

- كل حالة تحمل كلمة وأيقونة، فلا يعتمد المعنى على اللون وحده.
- «بانتظار تأكيد الدفع» وليس «لم يدفع» (المتطلبات، تاسعًا).
