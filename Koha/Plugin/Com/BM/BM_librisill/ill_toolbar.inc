<!-- ill-toolbar.inc -->
[% USE Koha %]
[% SET version = Koha.Version.maintenance %]

[% IF version <= '25.00.00' %]
<div id="navmenu">
    <div id="navmenulist">
        <div class="row">
        <div class="col-sm-6 col-md-12">
[% ELSE %]
<div class="circ-nav-menu sidebar_menu">
[% END %]    
    <h5>Fjärrlån in</h5>
    <ul>
        <li>
            <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=librisill_requests">Importera fjärrlån</a>
        </li>
        <li>
            <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=receive_ILL">Ankomstregistrera</a>
        </li>
        <li>
            <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=checkedout_ILL">Utlånade fjärrlån</a>
        </li>
        <li>
            <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=return_ILL">Återlämnade fjärrlån</a>
        </li>                
        <li>
            <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=deleted_ILL">Borttagna fjärrlån</a>
        </li>
    </ul>
    <h5>Fjärrlån ut</h5>
    <ul>
        <li>
            <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=librisill_incomings&archive=true">Fjärrlåneförfrågningar</a>
        </li>                
    </ul>
    <h5>Övrigt</h5>
    <ul>
        <li>
            <a href="#" id="printAdresslapp">Adresslapp</a>
        </li>                
    </ul>
[% IF version <= '25.00.00' %]
        </div>
    </div>
</div>
[% ELSE %]
</div>
[% END %]
<!-- /ill-toolbar.inc -->
