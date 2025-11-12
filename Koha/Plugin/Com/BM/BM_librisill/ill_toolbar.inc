<!-- ill-toolbar.inc -->
[% USE Koha %]
[% USE Branches %]
<div id="navmenu">
    <div id="navmenulist">
        <div class="row">
        <div class="col-sm-6 col-md-12">
            <h5>Fjärrlån in</h5>
            <ul>
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=librisill_requests">Importera fjärrlån</a>
                </li>
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=receive_ILL">Ankomstregistrera</a>
                </li>
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=checkedout_ILL">Utlånade fjärrlån</a>
                </li>
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=return_ILL">Återlämnade fjärrlån</a>
                </li>                
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=deleted_ILL">Borttagna fjärrlån</a>
                </li>
            </ul>
            <h5>Fjärrlån ut</h5>
            <ul>
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=librisill_incomings">Fjärrlåneförfrågningar</a>
                </li>
                <li>
                    <a href="/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=librisill_incomings&archive=true">Arkiverade förfrågningar</a>
                </li>                
            </ul>
        </div>
    </div>
</div>
<!-- /ill-toolbar.inc -->
