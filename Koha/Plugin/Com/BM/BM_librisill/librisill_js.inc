<script>

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
