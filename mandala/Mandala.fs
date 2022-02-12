
\ Mandalas für Gforth
\ Matthias Koch, Dezember 2021

\ -------------------------------------------------------------
\   Grafikspeicher und Zeichenroutinen definieren
\ -------------------------------------------------------------

800 constant xres 800 constant yres

create grafikspeicher xres yres * 3 * allot align
grafikspeicher xres yres * 3 * erase

: putpixel ( x y Farbe -- )
  >r xres * + 3 * grafikspeicher +
  r@     $FF and           over     c!
  r@   $FF00 and  8 rshift over 1 + c!
  r> $FF0000 and 16 rshift swap 2 + c!
;

: getpixel ( x y -- Farbe )
  xres * + 3 * grafikspeicher +
  dup     c@           >r
  dup 1 + c@  8 lshift >r
      2 + c@ 16 lshift r> or r> or
;

\ -------------------------------------------------------------
\   Zeichnen relativ zum Mittelpunkt des Bildes
\ -------------------------------------------------------------

: putpixel-offset ( x y Farbe -- )
  >r swap xres 2/ +
     swap yres 2/ + r> putpixel
;

: getpixel-offset ( x y -- Farbe )
  swap xres 2/ +
  swap yres 2/ + getpixel
;

\ -------------------------------------------------------------
\   Parameter vorbereiten
\ -------------------------------------------------------------

\         v Ausprobieren: 3, 6, 8, 12.
pi 2e0 f* 12e0 f/ fconstant theta

theta fcos 1e0 f- theta fsin f/ fconstant afloat
theta fsin                      fconstant bfloat

16 constant fractionalbits
1 fractionalbits 1- lshift constant rounding

1 fractionalbits lshift s>f afloat f* fround f>s constant aint
1 fractionalbits lshift s>f bfloat f* fround f>s constant bint

\ -------------------------------------------------------------
\   Mandala zeichnen
\ -------------------------------------------------------------

: arshift ( x u -- ) 0 ?do 2/ loop ;

: zykluspunkt ( x y -- x' y' )
  swap over ( y   x   y  ) aint * rounding + fractionalbits arshift + ( y  x' )
  swap over ( x'  y   x' ) bint * rounding + fractionalbits arshift + ( x' y' )
  swap over ( y'  x'  y' ) aint * rounding + fractionalbits arshift + ( y' x'' )
  swap ( x'' y' )
;

variable farbe

: zyklusmaler ( x-start y-start -- ) \ Zeichnet einen Zyklus

  2dup 2>r \ Startpunkt zur Enderkennung auf den Returnstack

  begin
    zykluspunkt
    2dup farbe @ putpixel-offset
    2dup 2r@ d=
  until

  2drop 2rdrop
;

variable laenge

: zykluslaenge ( x-start y-start -- laenge ) \ Bestimmt die Länge eines Zyklus

  0 laenge !

  2dup 2>r \ Startpunkt zur Enderkennung auf den Returnstack

  begin
    zykluspunkt
    1 laenge +!
    2dup 2r@ d=
  until

  2drop 2rdrop
  laenge @
;

$000000 constant hintergrund \ BBGGRR

: clrscr ( -- )
  xres 0 do yres 0 do j i hintergrund putpixel loop loop
;

require random.fs
31 seed ! \ Immer den gleichen Anfangswert für die Farben

: mandala ( -- )
   clrscr
   129 -128 do
     129 -128 do
      j i getpixel-offset hintergrund =  \ Pixel noch nicht gefärbt ?
      if
        j i zykluslaenge 128 >=  \ Zyklus lang und interessant ?
        if
          rnd farbe ! \ Neue Farbe aussuchen
          j i zyklusmaler
          ." Zyklus: " j 5 .r i 5 .r ."   Länge: " laenge @ 5 .r cr
        then
      then
    loop
  loop
;

mandala

\ -------------------------------------------------------------
\   Ausgabe des gezeichneten Bildes als PNM-Grafik
\ -------------------------------------------------------------

s" Mandala.pnm" w/o create-file throw value fd-grafik

create \f 13 c, align

s" P6"            fd-grafik write-file throw
\f 1              fd-grafik write-file throw
xres s>d <# #S #> fd-grafik write-file throw
s"  "             fd-grafik write-file throw
yres s>d <# #S #> fd-grafik write-file throw
\f 1              fd-grafik write-file throw
s" 255"           fd-grafik write-file throw
\f 1              fd-grafik write-file throw

grafikspeicher xres yres * 3 * fd-grafik write-file throw

fd-grafik close-file throw
bye
