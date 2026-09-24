import json, os

DATA = r'''
    const yes = true, no = false;
    return {
      yes, no,
      n0: 0, n1: 1, n2: 2, n3: 3, n4: 4, n45: 45, n52: 52, n38: 38, n84: 84, n120: 120,
      bookOpts: [{ value: 'queue', label: 'أقرب دور', icon: 'list-numbers' }, { value: 'hour', label: 'ساعة محددة', icon: 'clock' }],
      postponeOpts: [{ value: '1', label: 'دور واحد' }, { value: '2', label: 'دوران' }, { value: '3', label: '3 أدوار' }],
      periodOpts: [{ value: 'd', label: 'اليوم' }, { value: 'w', label: 'الأسبوع' }, { value: 'm', label: 'الشهر' }],
      navCustomer: [{ icon: 'calendar-check', label: 'حجزي' }, { icon: 'storefront', label: 'الصالون' }, { icon: 'receipt', label: 'السجل' }, { icon: 'user', label: 'حسابي' }],
      navStaff: [{ icon: 'list-numbers', label: 'طابوري' }, { icon: 'coins', label: 'الدفعات', badge: 2 }, { icon: 'coffee', label: 'استراحاتي' }, { icon: 'gear-six', label: 'المزيد' }],
      navManager: [{ icon: 'list-numbers', label: 'الطوابير' }, { icon: 'chart-bar', label: 'التقارير' }, { icon: 'storefront', label: 'الصالون' }, { icon: 'gear-six', label: 'الإعدادات' }],
      hairFeats: ['غسيل', 'تصفيف'], beardFeats: ['موس حار', 'زيت لحية'], kidFeats: ['حتى 12 سنة'], waxFeats: ['85 غ'], oilFeats: ['30 مل'],
      days: [{ day: 'السبت', from: '10:00 ص', to: '11:00 م' }, { day: 'الأحد', from: '10:00 ص', to: '11:00 م' }, { day: 'الاثنين', from: '10:00 ص', to: '11:00 م' },
        { day: 'الثلاثاء', from: '10:00 ص', to: '11:00 م' }, { day: 'الأربعاء', from: '10:00 ص', to: '11:00 م', today: true },
        { day: 'الخميس', from: '4:00 م', to: '1:00 ص' }, { day: 'الجمعة', closed: true }],
      impact: [{ name: 'فهد القحطاني', from: '10:40', to: '10:55', delta: 15 }, { name: 'عبدالله', from: '11:10', to: '11:45', delta: 35, notify: true },
        { name: 'ريان', from: '10:50 م', to: '11:25 م', pastClosing: true }],
      revSeries: [640, 910, 720, 1120, 860, 1010, 1240], accSeries: [12, 10, 9, 8, 8, 7, 7]
    };
'''

HEAD = '''<!doctype html>
<html lang="ar" dir="rtl">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
<link rel="stylesheet" href="ds/saloni/tokens.css">
<link rel="stylesheet" href="ds/saloni/components/bundle.css">
<script src="ds/saloni/components/bundle.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=El+Messiri:wght@500;600;700&amp;family=IBM+Plex+Sans+Arabic:wght@400;500;600&amp;family=IBM+Plex+Mono:wght@500&amp;display=swap">
<style>
body{{margin:0;background:#0e1726;font-family:"IBM Plex Sans Arabic",system-ui,sans-serif;color:#eaf1f8}}
a{{color:#8cc8e6}}a:hover{{color:#b3dcf0}}
</style>
</helmet>
<div dir="rtl" style="width: 390px; height: {h}px; box-sizing: border-box; background: var(--surface); color: var(--ink); font-family: var(--font-text); display: flex; flex-direction: column; position: relative; overflow: hidden">
{body}
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":{h}}}}}'>
class Component extends DCLogic {{
  renderVals() {{{data}  }}
}}
</script>
</body>
</html>
'''

def X(comp, attrs='', children=''):
    return f'<x-import component-from-global-scope="Saloni.{comp}" {attrs}>{children}</x-import>'

def link(href, text, kind='primary', size='md', icon=None, extra=''):
    ic = X('Icon', f'name="{icon}" size="{{{{n20}}}}"') if False else (X('Icon', f'name="{icon}"') if icon else '')
    return (f'<a href="{href}" class="dw-btn dw-btn-{kind} dw-btn-{size} dw-btn-block" '
            f'style="text-decoration: none; box-sizing: border-box{extra}">{ic}<span>{text}</span></a>')

def textlink(href, text):
    return f'<a href="{href}" style="font-size: 14px; line-height: 22px; color: var(--primary); text-underline-offset: 3px">{text}</a>'

def appbar(title, back=None, sub=None, right=''):
    b = (f'<a href="{back}" aria-label="رجوع" style="width: 44px; height: 44px; display: grid; place-items: center; color: var(--ink); '
         f'border-radius: 12px; background: var(--surface-raised); border: 1px solid var(--line)">'
         + X('Icon', 'name="caret-right"') + '</a>') if back else ''
    s = f'<p style="margin: 0; font-size: 13px; line-height: 20px; color: var(--ink-muted)">{sub}</p>' if sub else ''
    return (f'<header style="display: flex; align-items: center; gap: 12px; padding: 16px 16px 8px">{b}'
            f'<div style="flex-grow: 1"><h1 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 24px; line-height: 34px">{title}</h1>{s}</div>{right}</header>')

def section(title, inner, gap=10, extra=''):
    return (f'<section style="display: flex; flex-direction: column; gap: {gap}px{extra}">'
            f'<h2 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 18px; line-height: 28px">{title}</h2>{inner}</section>')

def scroll(inner, pad_bottom=24):
    return f'<main style="flex-grow: 1; display: flex; flex-direction: column; gap: 20px; padding: 8px 16px {pad_bottom}px; overflow: hidden">{inner}</main>'

def bottombar(inner):
    return (f'<div style="padding: 12px 16px 20px; background: var(--surface); border-top: 1px solid var(--line); display: flex; flex-direction: column; gap: 10px">{inner}</div>')

def nav(items, active=0):
    return X('BottomNav', f'items="{{{{{items}}}}}" active="{{{{n{active}}}}}"')

def salon_top():
    return ('<header style="display: flex; align-items: center; gap: 10px; padding: 16px 16px 8px">'
            '<span style="width: 40px; height: 40px; border-radius: 12px; background: var(--primary); color: var(--on-primary); display: grid; place-items: center; font-family: var(--font-display); font-weight: 700; font-size: 18px">ر</span>'
            '<div style="flex-grow: 1"><p style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 17px; line-height: 24px">صالون الراحة</p>'
            '<p style="margin: 0; font-size: 12px; line-height: 18px; color: var(--ink-muted)">حي النرجس · مفتوح حتى 11:00 م</p></div>'
            '<a href="C-About.dc.html" aria-label="حول الصالون" style="width: 44px; height: 44px; display: grid; place-items: center; border-radius: 50%; background: var(--surface-raised); color: var(--ink-muted); border: 1px solid var(--line)">'
            + X('Icon', 'name="storefront"') + '</a></header>')

def proto_hint(text, href):
    return (f'<p style="margin: 0; font-size: 12px; line-height: 18px; color: var(--ink-subtle); text-align: center">'
            f'معاينة: <a href="{href}" style="color: var(--steel)">{text}</a></p>')

S = {}  # name -> (title, height, body, page, row, col)

# ---------------- Customer ----------------
S['Main.dc.html'] = ('رمز الصالون', 844, f'''
<main style="flex-grow: 1; display: flex; flex-direction: column; justify-content: space-between; padding: 64px 24px 32px">
  <div style="display: flex; flex-direction: column; gap: 10px">
    <p style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 56px; line-height: 64px">صالوني</p>
    <p style="margin: 0; font-size: 17px; line-height: 28px; color: var(--ink-muted)">احجز دوري — وقتك محفوظ وأنت في مكانك.</p>
  </div>
  <div style="display: flex; flex-direction: column; gap: 16px">
    {X('TextField', 'label="رمز الصالون" value="RAHA-27" dir="ltr" hint="تجده على لوحة الصالون أو اطلبه من الحلاق"')}
    {link('C-About.dc.html', 'متابعة', 'primary', 'lg')}
    {link('C-About.dc.html', 'مسح رمز QR', 'secondary', 'md', 'qr-code')}
  </div>
  <p style="margin: 0; font-size: 13px; line-height: 20px; color: var(--ink-subtle); text-align: center">صاحب صالون؟ <a href="S-Signup.dc.html" style="color: var(--primary)">سجّل صالونك</a></p>
</main>''', 'customer')

S['C-About.dc.html'] = ('حول الصالون', 2020, f'''
<div style="height: 180px; background: var(--surface-elevated); border-bottom: 1px solid var(--line); display: grid; place-items: center; color: var(--ink-subtle); position: relative">
  <div style="display: flex; flex-direction: column; align-items: center; gap: 6px">{X('Icon', 'name="image" size="{{n32}}"').replace('{{n32}}','{{n45}}')}<span style="font-size: 12px">[صور الصالون — حتى 6]</span></div>
  <a href="Main.dc.html" aria-label="رجوع" style="position: absolute; top: 16px; right: 16px; width: 44px; height: 44px; display: grid; place-items: center; border-radius: 12px; background: var(--surface-raised); color: var(--ink); border: 1px solid var(--line)">{X('Icon', 'name="caret-right"')}</a>
</div>
<main style="display: flex; flex-direction: column; gap: 22px; padding: 0 16px 24px; margin-top: -32px; position: relative">
  <div style="display: flex; align-items: flex-end; gap: 12px">
    <span style="width: 72px; height: 72px; border-radius: 18px; background: var(--primary); color: var(--on-primary); display: grid; place-items: center; font-family: var(--font-display); font-weight: 700; font-size: 32px; border: 4px solid var(--surface)">ر</span>
    <div style="flex-grow: 1; padding-bottom: 4px">
      <h1 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 26px; line-height: 36px">صالون الراحة</h1>
    </div>
    {X('StatusBadge', 'status="done" tone="success" label="مفتوح الآن"')}
  </div>
  <p style="margin: 0; font-size: 15px; line-height: 26px; color: var(--ink-muted)">صالون رجالي في حي النرجس منذ 2015. ثلاثة حلاقين، وخدمة بلا انتظار عبر الحجز المسبق للدور.</p>
  {X('ContactBar', 'address="الرياض — حي النرجس، طريق أنس بن مالك" phone="+966 11 000 0000" whatsapp="+966 55 000 0000" maps="{{yes}}" instagram="@raha.salon"')}
  {section('الخدمات', X('CatalogItem', 'kind="service" name="حلاقة شعر" price="40" minutes="{{n38}}" description="قص وتدريج حسب طلبك." features="{{hairFeats}}"')
     + X('CatalogItem', 'kind="service" name="شعر ولحية" price="60" minutes="{{n45}}" description="قص الشعر مع تهذيب اللحية وتحديدها." features="{{beardFeats}}"')
     + X('CatalogItem', 'kind="service" name="حلاقة أطفال" price="30" minutes="{{n38}}" description="قصة هادئة وسريعة." features="{{kidFeats}}"'))}
  {section('المنتجات', X('CatalogItem', 'kind="product" name="واكس تصفيف مطفي" price="45" description="ثبات متوسط بلمسة طبيعية." features="{{waxFeats}}"')
     + X('CatalogItem', 'kind="product" name="زيت لحية" price="55" description="يرطب ويليّن اللحية." features="{{oilFeats}}"'))}
  {X('HoursList', 'open-now="{{yes}}" days="{{days}}"')}
</main>
{bottombar(link('C-Register.dc.html', 'سجّل واحجز دوري', 'primary', 'lg'))}''', 'customer')

S['C-Register.dc.html'] = ('إنشاء حساب', 844, f'''
{appbar('إنشاء حساب', 'C-About.dc.html', 'في صالون الراحة')}
{scroll(f"""
  {X('TextField', 'label="الاسم" value="محمد العتيبي"')}
  {X('TextField', 'label="رقم الهاتف" prefix="+966" dir="ltr" input-mode="tel" value="55 123 4567" hint="يستخدمه الصالون للتواصل معك فقط"')}
  {X('TextField', 'label="كلمة المرور" type="password" value="saloni2026" hint="8 أحرف على الأقل"')}
  <div style="border-radius: 16px; overflow: hidden; border: 1px solid var(--line)">{X('Switch', 'label="الدخول تلقائيًا" description="تذكّر حسابي على هذا الجهاز" checked="{{yes}}"')}</div>
  {X('Banner', 'tone="info" title="يراجع الصالون الحسابات الجديدة"', 'ستتمكن من الحجز بعد اعتماد حسابك. سنرسل لك تنبيهًا.')}
""")}
{bottombar(link('C-Book.dc.html', 'إنشاء الحساب', 'primary', 'lg') + '<p style="margin: 0; text-align: center; font-size: 14px; color: var(--ink-muted)">لديك حساب؟ <a href="C-Book.dc.html" style="color: var(--primary)">تسجيل الدخول</a></p>')}''', 'customer')

S['C-Book.dc.html'] = ('احجز دورك', 1180, f'''
{appbar('احجز دورك', None, 'صالون الراحة · اليوم الأربعاء')}
{scroll(f"""
  {section('الخدمات', X('ServiceChip', 'name="حلاقة شعر" minutes="{{n38}}" price="40"') + X('ServiceChip', 'name="شعر ولحية" minutes="{{n45}}" price="60" selected="{{yes}}"') + X('ServiceChip', 'name="حلاقة أطفال" minutes="{{n38}}" price="30"') + '<p style="margin: 0; font-size: 13px; color: var(--ink-subtle)">يمكنك اختيار أكثر من خدمة.</p>')}
  {section('الحلاق', X('BarberOption', 'fastest="{{yes}}" next-at="10:40" wait="بعد 25 د" selected="{{yes}}"') + X('BarberOption', 'name="خالد الحربي" next-at="10:55" wait="بعد 40 د"') + X('BarberOption', 'name="سعد العمري" unavailable="{{yes}}" reason="لا يعمل اليوم"'))}
  {section('الوقت', X('SegmentedControl', 'label="نوع الحجز" options="{{bookOpts}}"') + '<p style="margin: 0; font-size: 13px; line-height: 20px; color: var(--ink-subtle)">«أقرب دور» يضعك في أول وقت متاح. «ساعة محددة» تحجز لك ساعة تختارها اليوم.</p>')}
""", 16)}
{bottombar(f"""<div style="display: flex; justify-content: space-between; align-items: baseline"><span style="color: var(--ink-muted); font-size: 14px">الوقت المتوقع</span><span style="font-family: var(--font-display); font-size: 22px; font-weight: 600">10:40 ص</span></div>
<p style="margin: 0; font-size: 13px; color: var(--ink-muted)">شعر ولحية · نحو 45 دقيقة · 60 ر.س · الدفع في الصالون</p>
{link('C-Track.dc.html', 'احجز دوري', 'primary', 'lg')}
{proto_hint('طلب ساعة غير متاحة', 'C-Offer.dc.html')}""")}''', 'customer')

S['C-Offer.dc.html'] = ('أقرب وقت متاح', 844, f'''
{appbar('ساعة محددة', 'C-Book.dc.html', 'اختر الساعة التي تناسبك اليوم')}
{scroll(f"""
  {X('TextField', 'label="الساعة المطلوبة" value="5:00 م"')}
  {X('OfferCard', 'requested="5:00 م" offered="5:25 م" barber="خالد" seconds-left="{{n84}}" total="{{n120}}"')}
  <p style="margin: 0; font-size: 13px; line-height: 20px; color: var(--ink-muted)">لا نقدّم أحدًا على من حجز قبله، لذلك نعرض عليك أقرب وقت فعلي بعد الساعة التي طلبتها.</p>
""")}
{bottombar(link('C-Track.dc.html', 'احجز 5:25 م', 'primary', 'lg') + link('C-Book.dc.html', 'اختر ساعة أخرى', 'secondary'))}''', 'customer')

S['C-Track.dc.html'] = ('متابعة الحجز', 844, f'''
{salon_top()}
{scroll(f"""
  {X('EtaCard', 'eta="10:40" ampm="ص" status="waiting" barber="خالد الحربي" services="شعر ولحية · 45 دقيقة" updated="قبل دقيقة" original-eta="10:20" reason="تمديد خدمة سابقة"')}
  {X('QueueProgress', 'done="{{n3}}" ahead="{{n2}}" updated="قبل دقيقة"')}
  <div style="display: flex; gap: 10px">{link('C-Offer.dc.html', 'تعديل الوقت', 'secondary')}{link('C-Cancel.dc.html', 'إلغاء الحجز', 'ghost')}</div>
  {proto_hint('عندما يقترب دورك', 'C-Called.dc.html')}
""", 12)}
{nav('navCustomer', 0)}''', 'customer')

S['C-Called.dc.html'] = ('اقترب دورك', 844, f'''
{salon_top()}
{scroll(f"""
  {X('Banner', 'tone="warning" title="اقترب دورك — توجّه إلى الصالون الآن"', 'خالد ينهي خدمة الزبون الذي قبلك. مكانك محفوظ حتى تصل.')}
  {X('EtaCard', 'eta="11:05" ampm="ص" status="called" barber="خالد الحربي" services="شعر ولحية · 45 دقيقة" updated="الآن"')}
  {X('QueueProgress', 'done="{{n4}}" ahead="{{n0}}" updated="الآن"')}
  {proto_hint('عند انقطاع اتصال الصالون', 'C-Stale.dc.html')}
""", 12)}
{nav('navCustomer', 0)}''', 'customer')

S['C-Stale.dc.html'] = ('وقت تقديري', 844, f'''
{salon_top()}
{scroll(f"""
  {X('EtaCard', 'eta="11:15" ampm="ص" status="waiting" barber="خالد الحربي" services="حلاقة شعر · 30 دقيقة" live="{{no}}" stale-for="12 دقيقة"')}
  {X('QueueProgress', 'done="{{n2}}" ahead="{{n2}}" updated="قبل 12 دقيقة" note="لم يصلنا تحديث من الصالون — قد يكون الترتيب تغيّر"')}
  {X('Banner', 'tone="info"', 'سنحدّث وقتك ونرسل لك تنبيهًا فور عودة اتصال الصالون.')}
  {textlink('C-Track.dc.html', 'العودة إلى المتابعة')}
""", 12)}
{nav('navCustomer', 0)}''', 'customer')

S['C-Cancel.dc.html'] = ('إلغاء الحجز', 844, f'''
<div style="flex-grow: 1; background: var(--overlay)"></div>
<section style="background: var(--surface-raised); border-radius: 22px 22px 0 0; box-shadow: var(--shadow-3); padding: 24px 16px 28px; display: flex; flex-direction: column; gap: 14px">
  <h2 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 22px; line-height: 32px">إلغاء حجزك اليوم؟</h2>
  <p style="margin: 0; color: var(--ink-muted); font-size: 15px; line-height: 26px">حجزك عند خالد الحربي الساعة 10:40 ص. يمكنك الإلغاء في أي وقت قبل بدء خدمتك، ويمكنك الحجز من جديد لاحقًا.</p>
  {link('Main.dc.html', 'نعم، ألغِ الحجز', 'danger', 'lg')}
  {link('C-Track.dc.html', 'الإبقاء على الحجز', 'secondary')}
</section>''', 'customer')

# ---------------- Staff ----------------
S['S-Queue.dc.html'] = ('طابوري', 1120, f'''
{X('ConnectionBar', 'state="online"')}
{appbar('طابوري', None, 'خالد الحربي · الأربعاء', X('StatusBadge', 'status="pay_awaiting" size="sm" label="2 بانتظار الدفع"'))}
{scroll(f"""
  {X('CurrentServiceCard', 'customer="محمد العتيبي" services="شعر ولحية" started-at="10:05 ص" elapsed="{{n38}}" estimate="{{n45}}"')}
  <div style="display: flex; gap: 14px; justify-content: center">{textlink('S-Edit.dc.html', 'تعديل الخدمة')}<span style="color: var(--line-strong)">·</span>{textlink('S-Payments.dc.html', 'بعد الإنهاء: تأكيد الدفع')}</div>
  <div style="display: flex; align-items: center; justify-content: space-between">
    <h2 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 18px; line-height: 28px">التالون</h2>
    <a href="S-Walkin.dc.html" class="dw-btn dw-btn-secondary dw-btn-sm" style="text-decoration: none">{X('Icon', 'name="user-plus"')}<span>زبون حاضر</span></a>
  </div>
  <ul class="dw-queue">
    {X('QueueItem', 'position="1" name="فهد القحطاني" services="حلاقة شعر" eta="10:50" duration="30 د" status="called"')}
    {X('QueueItem', 'position="2" name="عبدالله" services="شعر ولحية" eta="11:20" duration="45 د" walk-in="{{yes}}"')}
    {X('QueueItem', 'position="3" name="ريان" services="تهذيب لحية" eta="12:00" duration="15 د" kind="requested" requested-at="12:00"')}
    {X('QueueItem', 'position="4" name="سلطان" services="حلاقة شعر" eta="12:15" duration="30 د"')}
  </ul>
  {proto_hint('فهد لم يصل بعد', 'S-Late.dc.html')}
  {proto_hint('انقطع الإنترنت', 'S-Offline.dc.html')}
""", 12)}
{nav('navStaff', 0)}''', 'staff')

S['S-Late.dc.html'] = ('زبون متأخر', 844, f'''
<div style="flex-grow: 1; background: var(--overlay)"></div>
<section style="background: var(--surface-raised); border-radius: 22px 22px 0 0; box-shadow: var(--shadow-3); padding: 24px 16px 28px; display: flex; flex-direction: column; gap: 14px">
  <div style="display: flex; align-items: center; gap: 10px">{X('Avatar', 'name="فهد القحطاني" size="{{n45}}"')}<div><h2 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 20px; line-height: 30px">فهد لم يصل بعد</h2>
  <p style="margin: 0; font-size: 13px; color: var(--ink-muted)">استُدعي 10:32 ص · موعده المتوقع 10:50 ص</p></div></div>
  <p style="margin: 0; font-size: 14px; line-height: 22px; color: var(--ink-muted)">القرار لك. التأجيل متاح مرة واحدة لهذا الحجز، ويُبلَّغ فهد تلقائيًا ويُستدعى التالي.</p>
  {X('SegmentedControl', 'label="عدد الأدوار" options="{{postponeOpts}}"')}
  {link('S-Queue.dc.html', 'تأجيل', 'primary', 'lg', 'arrow-u-up-left')}
  {link('S-Queue.dc.html', 'انتظاره قليلًا', 'secondary')}
  <div style="display: flex; flex-direction: column; gap: 4px">{X('Button', 'variant="danger" block="{{yes}}" disabled="{{yes}}"', 'لم يحضر')}
  <p style="margin: 0; text-align: center; font-size: 12px; color: var(--ink-subtle)">يُتاح بعد استخدام التأجيل</p></div>
</section>''', 'staff')

S['S-Edit.dc.html'] = ('تعديل الخدمة', 844, f'''
<div style="height: 96px; background: var(--overlay)"></div>
<section style="flex-grow: 1; background: var(--surface-raised); border-radius: 22px 22px 0 0; box-shadow: var(--shadow-3); padding: 24px 16px 28px; display: flex; flex-direction: column; gap: 14px">
  <h2 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 20px; line-height: 30px">تعديل خدمة محمد</h2>
  <p style="margin: 0; font-size: 13px; color: var(--ink-muted)">الخدمة جارية منذ 10:05 ص — لن يُعاد التوقيت من الصفر.</p>
  {X('ServiceChip', 'name="تهذيب لحية" minutes="{{n38}}" price="25"')}
  {X('ServiceChip', 'name="شعر ولحية" minutes="{{n45}}" price="60" selected="{{yes}}"')}
  {X('ImpactList', 'items="{{impact}}" note="سيصل تنبيه لعبدالله لأن وقته تغيّر أكثر من 30 دقيقة"')}
  <div style="flex-grow: 1"></div>
  {link('S-Queue.dc.html', 'تأكيد التعديل', 'primary', 'lg')}
  {link('S-Queue.dc.html', 'تراجع', 'ghost')}
</section>''', 'staff')

S['S-Walkin.dc.html'] = ('زبون حاضر', 844, f'''
{appbar('إضافة زبون حاضر', 'S-Queue.dc.html', 'يُضاف في آخر طابورك')}
{scroll(f"""
  {X('TextField', 'label="الاسم" value="عبدالعزيز"')}
  {X('TextField', 'label="رقم الهاتف" prefix="+966" dir="ltr" input-mode="tel" value="50 987 6543"')}
  {section('الخدمة', X('ServiceChip', 'name="حلاقة شعر" minutes="{{n38}}" price="40" selected="{{yes}}"') + X('ServiceChip', 'name="شعر ولحية" minutes="{{n45}}" price="60"'))}
  {X('Banner', 'tone="info"', 'الوقت المتوقع لهذا الزبون 12:45 م. إذا ثبّت التطبيق لاحقًا بنفس الرقم، يُربط سجله بحسابه.')}
""")}
{bottombar(link('S-Queue.dc.html', 'إضافة إلى الطابور', 'primary', 'lg'))}''', 'staff')

S['S-Offline.dc.html'] = ('بدون اتصال', 1000, f'''
{X('ConnectionBar', 'state="offline" since="10:32" pending="{{n2}}"')}
{appbar('طابوري', None, 'خالد الحربي · الأربعاء')}
{scroll(f"""
  {X('CurrentServiceCard', 'customer="محمد العتيبي" services="شعر ولحية" started-at="10:05 ص" elapsed="{{n52}}" estimate="{{n45}}"')}
  {X('Banner', 'tone="warning" title="الحجز عن بعد متوقف عندك"', 'عملك المحجوز أقل من ساعتين، فأوقفنا الحجوزات الجديدة حتى يعود الاتصال. ما تسجله الآن يُحفظ ويُزامن تلقائيًا.')}
  <div style="display: flex; align-items: center; justify-content: space-between">
    <h2 style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 18px; line-height: 28px">التالون</h2>
    {X('Button', 'variant="secondary" size="sm" icon="user-plus" disabled="{{yes}}"', 'زبون حاضر')}
  </div>
  <ul class="dw-queue">
    {X('QueueItem', 'position="1" name="فهد القحطاني" services="حلاقة شعر" eta="10:57" duration="30 د" status="called"')}
    {X('QueueItem', 'position="2" name="عبدالله" services="شعر ولحية" eta="11:27" duration="45 د" walk-in="{{yes}}"')}
  </ul>
  {textlink('S-Queue.dc.html', 'عاد الاتصال')}
""", 12)}
{nav('navStaff', 0)}''', 'staff')

PAY_PENDING = (
    '<article style="background: var(--surface-raised); border: 1px solid var(--warning); border-radius: 16px; padding: 16px; display: flex; flex-direction: column; gap: 10px">'
    '<div style="display: flex; justify-content: space-between; align-items: baseline"><span style="font-family: var(--font-display); font-weight: 600; font-size: 17px">محمد العتيبي</span><span style="font-family: var(--font-display); font-size: 22px; font-weight: 600">60 ر.س</span></div>'
    '<p style="margin: 0; font-size: 13px; color: var(--ink-muted)">شعر ولحية · انتهت 10:52 ص</p>'
    + link('S-Queue.dc.html', 'تأكيد استلام الدفع', 'primary', 'lg', 'coins') + '</article>'
    '<article style="background: var(--surface-raised); border: 1px solid var(--line); border-radius: 16px; padding: 16px; display: flex; align-items: center; gap: 12px">'
    '<div style="flex-grow: 1"><p style="margin: 0; font-family: var(--font-display); font-weight: 600; font-size: 16px">ماجد</p><p style="margin: 0; font-size: 13px; color: var(--ink-muted)">حلاقة شعر · 9:40 ص</p></div>'
    '<span style="font-family: var(--font-display); font-weight: 600; font-size: 18px">40 ر.س</span>'
    + X('Button', 'variant="secondary" size="sm"', 'تأكيد') + '</article>')
PAY_DONE = ('<div style="display: flex; justify-content: space-between; align-items: center; padding: 12px 0; border-bottom: 1px solid var(--line)"><span>سامي · حلاقة شعر</span>'
    + X('StatusBadge', 'status="pay_confirmed" size="sm"') + '</div>'
    '<div style="display: flex; justify-content: space-between; align-items: center; padding: 12px 0"><span>بدر · شعر ولحية</span>'
    + X('StatusBadge', 'status="pay_confirmed" size="sm"') + '</div>')
PAY_MAIN = section('بانتظار التأكيد', PAY_PENDING) + section('مؤكدة', PAY_DONE)
S['S-Payments.dc.html'] = ('الدفعات', 844, X('ConnectionBar', 'state="online"') + appbar('الدفعات', None, 'اليوم') + scroll(PAY_MAIN, 12) + nav('navStaff', 1), 'staff')

# ---------------- Manager ----------------
ROW = '<div style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); padding: 12px 14px; font-size: 14px; border-top: 1px solid var(--line)">' 
TABLE = ('<div style="background: var(--surface-raised); border: 1px solid var(--line); border-radius: 16px; overflow: hidden">'
  '<div style="display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); padding: 10px 14px; font-size: 12px; color: var(--ink-muted)"><span>الحلاق</span><span>زيارات</span><span>الإيراد (ر.س)</span><span>متوسط المدة</span></div>'
  + ''.join(ROW + ''.join(f'<span>{c}</span>' for c in r) + '</div>' for r in [('خالد','12','610','34 د'),('سعد','9','420','38 د'),('ماجد','6','210','29 د')]) + '</div>')
TILES = ('<div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px">'
  + X('StatTile', 'label="الإيراد المؤكد" value="1,240" unit="ر.س" delta="+12% عن الأربعاء الماضي" delta-tone="success" series="{{revSeries}}"')
  + X('StatTile', 'label="بانتظار التأكيد" value="100" unit="ر.س" delta="زيارتان" delta-tone="warning"')
  + X('StatTile', 'label="الزيارات المنجزة" value="27" delta="2 لم يحضر · 1 ملغى"')
  + X('StatTile', 'label="دقة الأوقات المتوقعة" value="±7" unit="د" series="{{accSeries}}"') + '</div>')
PEND = X('Banner', 'tone="warning" title="دفعتان بانتظار التأكيد"', 'عند خالد: محمد (60 ر.س) وماجد (40 ر.س).') + X('Banner', 'tone="info" title="حساب جديد ينتظر الاعتماد"', 'محمد العتيبي — سجّل قبل 10 دقائق.')
REP_MAIN = X('SegmentedControl', 'label="الفترة" options="{{periodOpts}}"') + TILES + section('حسب الحلاق', TABLE) + section('المعلّقات', PEND)
S['M-Reports.dc.html'] = ('التقارير', 1180, appbar('التقارير', None, 'صالون الراحة') + scroll(REP_MAIN, 12) + nav('navManager', 1), 'manager')

SROWS = ''.join(f'<div style="display: flex; justify-content: space-between; align-items: center; padding: 14px 16px; background: var(--surface-raised); border-top: 1px solid var(--line)"><span>{a}</span><span style="color: var(--primary); font-weight: 600">{b}</span></div>'
    for a, b in [('الحجوزات النشطة لكل زبون', '1'), ('فتح الحجز قبل الافتتاح', '60 د'), ('هامش التنبيه الإلزامي', '30 د'), ('نافذة الانقطاع القصوى', 'ساعتان'), ('مدة حجز العرض', 'دقيقتان'), ('تنبيه تجاوز المدة', '100%')])
SET_MAIN = ('<div style="border: 1px solid var(--line); border-radius: 16px; overflow: hidden; display: flex; flex-direction: column; gap: 1px; background: var(--line)">'
  + X('Switch', 'label="اشتراط اعتماد الحسابات" description="لا يحجز الزبون الجديد حتى تعتمد حسابه" checked="{{yes}}"')
  + X('Switch', 'label="الأرقام العربية المشرقية" description="عرض ٠١٢٣ بدل 0123"') + '</div>'
  + section('الحجز', '<div style="border: 1px solid var(--line); border-radius: 16px; overflow: hidden; margin-top: -1px">' + SROWS + '</div>')
  + section('فترات الحاضرين فقط', X('Banner', 'tone="info"', 'لا تُقبل حجوزات التطبيق في هذه الفترات، ويخدم فيها الحلاق زبائن حاضرين.')
    + '<div style="display: flex; justify-content: space-between; align-items: center; padding: 14px 16px; background: var(--surface-raised); border: 1px solid var(--line); border-radius: 16px"><span>كل الحلاقين · يوميًا</span><span style="font-weight: 600">4:00 – 6:00 م</span></div>'))
S['M-Settings.dc.html'] = ('الإعدادات', 1000, appbar('الإعدادات', None, 'تسري على الصالون كله') + scroll(SET_MAIN, 12) + nav('navManager', 3), 'manager')

S['M-Salon.dc.html'] = ('ملف الصالون', 1280, f'''
{appbar('ملف الصالون', None, 'يظهر للزبائن في «حول الصالون»')}
{scroll(f"""
  <div style="display: flex; align-items: center; gap: 12px"><span style="width: 64px; height: 64px; border-radius: 16px; background: var(--primary); color: var(--on-primary); display: grid; place-items: center; font-family: var(--font-display); font-weight: 700; font-size: 28px">ر</span>{X('Button', 'variant="secondary" size="sm" icon="image"', 'تغيير الشعار')}</div>
  {X('TextField', 'label="اسم الصالون" value="صالون الراحة"')}
  {X('TextField', 'label="النبذة" value="صالون رجالي في حي النرجس منذ 2015."')}
  {X('TextField', 'label="العنوان" value="الرياض — حي النرجس، طريق أنس بن مالك"')}
  {X('Button', 'variant="secondary" icon="map-pin" block="{{yes}}"', 'تحديد الموقع من مكاني الحالي')}
  {X('TextField', 'label="واتساب" prefix="+966" dir="ltr" value="55 000 0000"')}
  {section('الخدمات والمنتجات', X('CatalogItem', 'kind="service" name="شعر ولحية" price="60" minutes="{{n45}}" description="قص الشعر مع تهذيب اللحية."') + X('CatalogItem', 'kind="product" name="واكس تصفيف مطفي" price="45" description="ثبات متوسط."') + X('Button', 'variant="ghost" icon="plus" block="{{yes}}"', 'إضافة خدمة أو منتج'))}
""", 12)}
{nav('navManager', 2)}''', 'manager')

S['S-Signup.dc.html'] = ('تسجيل صالون', 844, f'''
{appbar('سجّل صالونك', 'Main.dc.html', 'الخطوة 4 من 4')}
<main style="flex-grow: 1; display: flex; flex-direction: column; justify-content: center; padding: 16px">
  {X('EmptyState', 'icon="hourglass-medium" title="صالونك بانتظار التفعيل" body="أرسلنا بياناتك إلى فريق صالوني. بعد التفعيل يظهر صالونك للزبائن، وتصلك رسالة هنا."')}
  <div style="display: flex; flex-direction: column; gap: 10px">
    <div style="display: flex; justify-content: space-between; padding: 12px 16px; background: var(--surface-raised); border: 1px solid var(--line); border-radius: 12px"><span style="color: var(--ink-muted)">رمز صالونك</span><bdi style="font-family: var(--font-mono); letter-spacing: .08em">RAHA-27</bdi></div>
    {link('M-Salon.dc.html', 'أكمل ملف الصالون', 'secondary')}
  </div>
</main>''', 'manager')

# ---------------- write ----------------
os.makedirs('project', exist_ok=True)
layout = {
  'customer': ['Main.dc.html', 'C-About.dc.html', 'C-Register.dc.html', 'C-Book.dc.html', 'C-Offer.dc.html', 'C-Track.dc.html', 'C-Called.dc.html', 'C-Stale.dc.html', 'C-Cancel.dc.html'],
  'staff': ['S-Queue.dc.html', 'S-Late.dc.html', 'S-Edit.dc.html', 'S-Walkin.dc.html', 'S-Offline.dc.html', 'S-Payments.dc.html'],
  'manager': ['S-Signup.dc.html', 'M-Salon.dc.html', 'M-Reports.dc.html', 'M-Settings.dc.html'],
}
titles = {'customer': 'تطبيق الزبون', 'staff': 'تطبيق الحلاق', 'manager': 'المدير وصاحب الصالون'}
boards, order, notes = {}, [], {}
y = 0
for page, files in layout.items():
    x = 0
    notes['t-' + page] = {'x': 0, 'y': y - 240, 'text': titles[page], 'kind': 'title1', 'maxW': 1800}
    rowh = 0
    for f in files:
        title, h, body, _ = S[f]
        html = HEAD.format(title=title, h=h, body=body.strip(), data=DATA)
        open('project/' + f, 'w').write(html)
        boards[f] = {'x': x, 'y': y, 'w': 390, 'h': h, 'title': title, 'is_interactive': True}
        order.append(f)
        x += 390 + 80
        rowh = max(rowh, h)
    y += rowh + 120 + 240
canvas = {'v': 3, 'createdOnFiles': {'v': 1, 'at': '__NOW__'}, 'title': 'صالوني — النموذج الأولي', 'launch': {'view': 'canvas'}, 'pages': [],
          'boards': boards, 'order': order, 'notes': notes,
          'designSystems': [{'title': 'صالوني', 'namespace': 'saloni', 'artifact': 'https://claude.ai/artifact/WGQaBmAoKyMTJEGt8wZsua', 'version': None, 'copiedAt': '__NOW__'}]}
json.dump(canvas, open('project/canvas.json', 'w'), ensure_ascii=False, indent=1)
print(len(S), 'screens')
