<!-- librisill_js.inc -->
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


    $('.adresslapplink').each(function () {
        var sigel = $(this).attr('sigel');
        var homebranch = $(this).attr('homebranch');
        $(this).on('click', function (event) {
            event.preventDefault();
            printDiv(sigel, homebranch);
        });
    });


    $('#modalprintadresslapp').on('click', function(event) {
        event.preventDefault();
        openAdresslappModal();
    });


    function openAdresslappModal() {
        $('#adresslappModal').remove();
        $('body').append(`
            <div class="modal fade" id="adresslappModal" tabindex="-1" role="dialog" aria-labelledby="adresslappModalLabel" aria-hidden="true">
                <div class="modal-dialog" role="document">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h3 class="modal-title" id="printAdresslappModalLabel">Skriv ut adresslapp</h3>
                        </div>
                        <div class="modal-body">
                            <span>Mottagande bibliotek: </span>
                            <input id="receivingsigel" type="text" placeholder="Ange sigel för bibliotek...">
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Stäng</button>
                            <button id="printAdresslapp" type="button" class="btn btn-primary">Skriv ut</button>
                        </div>
                    </div>
                </div>
            </div> 
        `);

        
        const sigelinput = document.querySelector('#receivingsigel');

        sigelinput.addEventListener('keypress', function (event) {
            if (event.keyCode === 13) {
                $('#printAdresslapp').trigger('click');
            }
        });

        $('#printAdresslapp').on('click', function(event) {
            event.preventDefault();        
            let homebranch = $('.logged-in-branch-code:first').text().toLowerCase();
            homebranch = homebranch.charAt(0).toUpperCase() + homebranch.slice(1);
            let sigel = $('#receivingsigel').val();
            sigel = sigel.toLowerCase();
            sigel = sigel.charAt(0).toUpperCase() + sigel.slice(1);            
            $('#adresslappModal').modal('toggle');            
            if (sigel) {
                if (sigel == homebranch) {
                    alert('Du har angett ditt egna sigel, var god ange ett annat.');
                } else {
                    printDiv(sigel, homebranch);
                }
            }
        });

        $('#adresslappModal').on('shown.bs.modal', function (e) {
            $('#receivingsigel').focus();
        });

        $('#adresslappModal').modal('toggle');
        
    }


    function printDiv(sigel, homebranch) {
            
        $.ajax({
            type: "GET",
            cache: true,
            url: `/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ACom%3A%3ABM%3A%3ABM_librisill&method=tool&subroutine=getlibdata&sigel=${sigel}`,
            success: function (bibinfo) {  

                if (bibinfo.count > 1) {                  
                    var sigel0 = bibinfo.libraries[0];
                    var sigel1 = bibinfo.libraries[1];
                    var branchinfo;
                    var sigelinfo;
                    //console.log(`sigel0: ${sigel0.library_code}  sigel1: ${sigel1.library_code}  homebranch: ${homebranch}`);
                    if (sigel0.library_code == homebranch) {
                        branchinfo = sigel0;
                        sigelinfo = sigel1;
                    } else {
                        branchinfo = sigel1;
                        sigelinfo = sigel0;
                    }
                                        
                    let printWindow = window.open('', '', 'height=700, width=900');
                    printWindow.document.open();
                    printWindow.document.write(`
                        <html>
                        <head>
                            <title>Adresslapp</title>
                            <style type="text/css">
                                body { font-family: Arial, sans-serif; }
                                h1 { color: #333; }
                                .adresslapp { width: 400px; border: 2px dotted #333 !important; padding: 30px; }
                                #sender td { color:#888; font-size: small; }
                                #receiver { padding-top: 30px; padding-left: 180px; }
                                #receiver td { color:#000; font-size: large; }
                                @media print {
                                    .adresslapp { width: 400px; border: 2px dotted #333 !important; padding: 30px; }
                                    #sender td { color:#888; font-size: small; }
                                    #receiver { padding-top: 30px; padding-left: 180px; }
                                    #receiver td { color:#000; font-size: large; }
                                }
                            </style>
                        </head>
                        <body>
                            <div class="adresslapp">
                                <span style="float: right; font-size: xx-large;">A-post</span>
                                <div>
                                    <table id="sender" style="">
                                        <tr>
                                            <td>Avsändare:</td>
                                        </tr>
                                        <tr>
                                            <td>${branchinfo.name}</td>
                                        </tr>
                                        <tr>
                                            <td>${branchinfo.address1}</td>
                                        </tr>
                                        <tr>
                                            <td>${branchinfo.zip_code} ${branchinfo.city}</td>
                                        </tr>
                                    </table>
                                </div>
                                <div>
                                    <table id="receiver" style="">
                                        <tr>
                                            <td style="font-size: small !important;">Mottagare:</td>
                                        </tr>
                                        <tr>
                                            <td>${sigelinfo.name}</td>
                                        </tr>
                                        <tr>
                                            <td>${sigelinfo.department}</td>
                                        </tr>
                                        <tr>
                                            <td>${sigelinfo.address1}</td>
                                        </tr>
                                        <tr>
                                            <td>${sigelinfo.zip_code} ${sigelinfo.city}</td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                            
                        </body>
                        </html>
                    `);

                    //printWindow.document.close();
                    printWindow.print();
                    printWindow.close();
                } else {
                    alert('Biblioteket finns inte, kontrollera att du skrev rätt sigel!');
                }
            }
        });
    }

</script>
<!-- /librisill_js.inc -->
