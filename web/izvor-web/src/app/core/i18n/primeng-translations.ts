import type { Translation } from 'primeng/api';
import type { Locale } from './locale.model';

export const PRIMENG_TRANSLATIONS: Record<Locale, Translation> = {
  'en': {
    accept: 'Yes',
    reject: 'No',
    cancel: 'Cancel',
    clear: 'Clear',
    apply: 'Apply',
    today: 'Today',
    weekHeader: 'Wk',
    emptyMessage: 'No results found',
    emptyFilterMessage: 'No results found',
    dayNames: ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'],
    dayNamesShort: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    dayNamesMin: ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'],
    monthNames: ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'],
    monthNamesShort: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    firstDayOfWeek: 1
  },
  'sr-latn': {
    accept: 'Da',
    reject: 'Ne',
    cancel: 'Otkaži',
    clear: 'Obriši',
    apply: 'Primeni',
    today: 'Danas',
    weekHeader: 'Ned',
    emptyMessage: 'Nema rezultata',
    emptyFilterMessage: 'Nema rezultata',
    dayNames: ['Nedelja', 'Ponedeljak', 'Utorak', 'Sreda', 'Četvrtak', 'Petak', 'Subota'],
    dayNamesShort: ['Ned', 'Pon', 'Uto', 'Sre', 'Čet', 'Pet', 'Sub'],
    dayNamesMin: ['Ne', 'Po', 'Ut', 'Sr', 'Če', 'Pe', 'Su'],
    monthNames: ['Januar', 'Februar', 'Mart', 'April', 'Maj', 'Jun', 'Jul', 'Avgust', 'Septembar', 'Oktobar', 'Novembar', 'Decembar'],
    monthNamesShort: ['Jan', 'Feb', 'Mar', 'Apr', 'Maj', 'Jun', 'Jul', 'Avg', 'Sep', 'Okt', 'Nov', 'Dec'],
    firstDayOfWeek: 1
  },
  'sr-cyrl': {
    accept: 'Да',
    reject: 'Не',
    cancel: 'Откажи',
    clear: 'Обриши',
    apply: 'Примени',
    today: 'Данас',
    weekHeader: 'Нед',
    emptyMessage: 'Нема резултата',
    emptyFilterMessage: 'Нема резултата',
    dayNames: ['Недеља', 'Понедељак', 'Уторак', 'Среда', 'Четвртак', 'Петак', 'Субота'],
    dayNamesShort: ['Нед', 'Пон', 'Уто', 'Сре', 'Чет', 'Пет', 'Суб'],
    dayNamesMin: ['Не', 'По', 'Ут', 'Ср', 'Че', 'Пе', 'Су'],
    monthNames: ['Јануар', 'Фебруар', 'Март', 'Април', 'Мај', 'Јун', 'Јул', 'Август', 'Септембар', 'Октобар', 'Новембар', 'Децембар'],
    monthNamesShort: ['Јан', 'Феб', 'Мар', 'Апр', 'Мај', 'Јун', 'Јул', 'Авг', 'Сеп', 'Окт', 'Нов', 'Дец'],
    firstDayOfWeek: 1
  }
};
