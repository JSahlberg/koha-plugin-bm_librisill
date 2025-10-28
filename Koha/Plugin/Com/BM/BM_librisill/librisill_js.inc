<script>

    $('#btn_deleted_ill').on('click', function (e) {
        e.preventDefault();
        var title = window.prompt('Vilken titel vill du söka efter?');

        if (title != null) {
            window.location.href = `/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=deleted_ill&search=${title}`;
        }

    });

    $('.ill_table tbody tr').each(function () {
        $(this).on('mouseover', function () {
            bgcolor = $(this).children('td:first').css('background-color');
            $(this).children('td').each(function () {
                if ($(this).css('background-color') == bgcolor) {
                    $(this).css('background-color', 'rgb(211, 244, 188)');
                }
            });
        });
        $(this).on('mouseout', function () {
            $(this).children('td').each(function () {
                if ($(this).css('background-color') == 'rgb(211, 244, 188)') {
                    $(this).css('background-color', bgcolor);
                }
            });
        });
    });

</script>
