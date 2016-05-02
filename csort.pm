# Modul pro asistenci s českým řazením textů, pokud nedůvěřujeme locale.
package csort;
use utf8; # říct Perlu, že konstantní řetězce ve zdrojáku jsou v UTF



INIT
{
    # Definice abecedních pořádků. Jednotlivá písmena jsou oddělena znakem =
    # nebo <, podle toho, zda se písmeno v prvním čtení považuje za rovnocenné
    # předcházejícímu, nebo za větší než předcházející. Pokud jsou si dvě celá
    # slova rovna, nastoupí druhé čtení a slova se porovnají přímo podle pořadí
    # písmen v této definici, bez ohledu na znaménka, která je oddělují.
    # Písmeno se může skládat i z více znaků (např. české "ch"). Znaky, které
    # nejsou v definici obsaženy, se při třídění v prvním čtení ignorují, jako
    # kdyby je slovo vůbec neobsahovalo.
    my %order;
    # Další ekvivalentní písmena.
    my $a = join("=", map{chr(hex($_))}("C0", "C2", "C3", "C4", "C5", "C6", "E0", "E1", "E2", "E3", "E4", "E5", "E6", "100", "101", "102", "103", "104", "105", "1CD", "1CE"));
    my $e = join("=", map{chr(hex($_))}("C8", "CA", "CB", "E8", "EA", "EB", "112", "113", "114", "115", "116", "117", "118", "119"));
    my $g = join("=", map{chr(hex($_))}("11E", "11F"));
    my $i = join("=", map{chr(hex($_))}("CC", "CE", "CF", "EC", "EE", "EF", "128", "129", "12A", "12B", "12C", "12D", "12E", "12F", "130", "131", "132", "133", "1CF", "1D0"));
    my $n = join("=", map{chr(hex($_))}("D1", "F1", "143", "144", "145", "146", "149", "14A", "14B"));
    my $o = join("=", map{chr(hex($_))}("D2", "D4", "D5", "D6", "D8", "F2", "F4", "F5", "F6", "F8", "14C", "14D", "14E", "14F", "150", "151", "152", "153", "1D1", "1D2"));
    my $u = join("=", map{chr(hex($_))}("D9", "DB", "DC", "F9", "FB", "FC", "168", "169", "16A", "16B", "16C", "16D", "170", "171", "172", "173", "1D3", "1D4", "1D5", "1D6", "1D7", "1D8", "1D9", "1DA", "1DB", "1DC"));
    # Cyrilice ABVG...EJuJa = x410-x42F velké a x430-x44F malé; uzbecké U je 40E,45E; kazašské K je 49A,49B
    my @cyr;
    for(my $i = hex("410"); $i<=hex("42F"); $i++)
    {
        my $pismeno = chr($i)."=".chr($i+32);
        # kazašské K (Q)
        if($i==hex("41A"))
        {
            $pismeno .= "=".chr(hex("49A"))."=".chr(hex("49B"));
        }
        # uzbecké U (O)
        if($i==hex("423"))
        {
            $pismeno .= "=".chr(hex("40E"))."=".chr(hex("45E"));
        }
        push(@cyr, $pismeno);
    }
    my $cyr = join("<", @cyr);
    $order{cs} = "0<1<2<3<4<5<6<7<8<9<a=A=á=Á=$a<b=B<c=C<č=Č=ç=Ç<d=D=ď=Ď<e=E=é=É=ě=Ě=$e<f=F<g=G=$g<h=H<ch=Ch=CH<i=I=í=Í=$i<j=J<k=K<l=L<m=M<n=N=ň=Ň=$n<o=O=ó=Ó=$o<p=P<q=Q<r=R<ř=Ř<s=S<š=Š=ś=Ś<t=T=ť=Ť<u=U=ú=Ú=ů=Ů=$u<v=V<w=W<x=X<y=Y=ý=Ý<z=Z<ž=Ž=ż=Ż<$cyr";
    $order{en} = "0<1<2<3<4<5<6<7<8<9<a=A=á=Á=$a<b=B<c=C=č=Č=ç=Ç<d=D=ď=Ď<e=E=é=É=ě=Ě=$e<f=F<g=G=$g<h=H<i=I=í=Í=$i<j=J<k=K<l=L<m=M<n=N=ň=Ň=$n<o=O=ó=Ó=$o<p=P<q=Q<r=R=ř=Ř<s=S=š=Š=ś=Ś<t=T=ť=Ť<u=U=ú=Ú=ů=Ů=$u<v=V<w=W<x=X<y=Y=ý=Ý<z=Z=ž=Ž=ż=Ż";
    # Předzpracované popisy řazení uložit do globálního hashe.
    while(my ($klic, $hodnota) = each(%order))
    {
        $popis{$klic} = vytvorit_tabulku_tridicich_hodnot($hodnota);
    }
    # Výchozí jazyk je čeština.
    $popis{""} = $popis{cs};
}



#------------------------------------------------------------------------------
# Převede lidsky čitelný popis abecedního řazení v určitém jazyce na číselné
# třídící hodnoty. Vytvoří i další jazykově závislé pomůcky, např. regulární
# výraz pro nalezení písmene ve slově.
#------------------------------------------------------------------------------
sub vytvorit_tabulku_tridicich_hodnot
{
    my $order = shift; # textový popis řazení v daném jazyce
    my %popis; # výstupní hash
    my @order = split(//, $order);
    my @pismena = split(/[=<]/, $order);
    my $i_pismena = 0;
    my $aktualni_ordval = 1;
    for(my $i = 0; $i<=$#order; $i++)
    {
        if($order[$i] eq "<")
        {
            $aktualni_ordval++;
        }
        elsif($order[$i] ne "=")
        {
            $popis{ordval1}{$pismena[$i_pismena]} = $aktualni_ordval;
            $popis{ordval2}{$pismena[$i_pismena]} = $i_pismena;
            $i_pismena++;
            while($i<$#order && $order[$i+1] !~ m/[<=]/)
            {
                $i++;
            }
        }
    }
    # Vytvořit seznam písmen seřazený sestupně podle počtu znaků.
    # (Ve slově se přednostně hledají písmena skládající se z více znaků.)
    @pismena = sort {length($b) <=> length($a)} @pismena;
    # regulární výraz pro identifikaci známého písmene
    $popis{rv_pismena} = join("|", @pismena);
    return \%popis;
}



#------------------------------------------------------------------------------
# Rozloží vstup na písmena (případně víceznaková).
# Zahodí znaky, které nejsou písmeny.
#------------------------------------------------------------------------------
sub rozlozit_na_pismena
{
    my $vstup = shift;
    my $rv_pismena = shift;
    my @vysledek;
    while($vstup ne "")
    {
        my $pismeno;
        my $zbytek;
        if($vstup =~ m/^($rv_pismena)(.*)/)
        {
            $pismeno = $1;
            $zbytek = $2;
            push(@vysledek, $pismeno);
        }
        elsif($vstup =~ m/^(\w)(.*)/)
        {
            # Kvůli Unicodu: Něco, s čím naše třídění nepočítá, ale podle Perlu
            # je to písmeno, nezahodit, nýbrž taky uložit.
            $pismeno = $1;
            $zbytek = $2;
            push(@vysledek, $pismeno);
        }
        else
        {
            $vstup =~ m/^.(.*)/;
            $zbytek = $1;
        }
        $vstup = $zbytek;
    }
    #    print join("-", @vysledek) . "\n";
    return @vysledek;
}



#------------------------------------------------------------------------------
# Vytvoří podle řetězce tzv. řetězec třídících hodnot. Ten sestává pouze
# z číslic. Je zaručené, že porovnání dvou takovýchto řetězců odpovídá
# porovnání původních řetězců podle české abecedy.
#------------------------------------------------------------------------------
sub zjistit_tridici_hodnoty
{
    my $ret = shift;
    my $jazyk = shift; # kód jazyka, jehož řazení se má použít
    my $ordval1 = $popis{$jazyk}{ordval1};
    my $ordval2 = $popis{$jazyk}{ordval2};
    my $rv_pismena = $popis{$jazyk}{rv_pismena};
    my @retpis = rozlozit_na_pismena($ret, $rv_pismena);
    my $vysledek;
    my $i;
    for($i = 0; $i<=$#retpis; $i++)
    {
        # DZ 19.5.2005: Zatím nemám jasno, jak řešit Unicodové znaky. Není možné
        # zapsat do třídícího řetězce celý Unicode a nebylo by to ani rozumné,
        # protože u většiny písmen bude pořadí kopírovat pořadí Unicodu. Zatím
        # to tedy udělám tak, že všechny znaky s kódem od 500 nahoru (zhruba hranice
        # latinky) se budou považovat za písmena a dostanou třídící hodnotu, která
        # bude rovna jejich unikódu.
        if($ordval1->{$retpis[$i]} eq "" && ord($retpis[$i])>=500)
        {
            $ordval1->{$retpis[$i]} = ord($retpis[$i]);
        }
        $vysledek = $vysledek . sprintf("%05d", $ordval1->{$retpis[$i]});
    }
    $vysledek = $vysledek . " ";
    for($i = 0; $i<=$#retpis; $i++)
    {
        $vysledek = $vysledek . sprintf("%02d", $ordval2->{$retpis[$i]});
    }
    $vysledek = $vysledek . " $ret";
    return $vysledek;
}



#------------------------------------------------------------------------------
# Setřídí pole řetězcově podle české abecedy.
#------------------------------------------------------------------------------
sub csort
{
    my @pole = @_;
    # Zjistit třídící hodnoty pro všechny prvky pole.
    my %trid;
    foreach my $prvek (@pole)
    {
        $trid{$prvek} = zjistit_tridici_hodnoty($prvek, 'cs');
    }
    # Setřídit pole a výsledek vrátit.
    return sort {$trid{$a} cmp $trid{$b}} @pole;
}



1;
