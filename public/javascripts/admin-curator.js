$(document).ready(function() {
  $('a.curator_status').click(function() {
    EOL.ajax_submit($(this), {update: $(this).parent().parent(), url: $(this).attr('href'), data: "class=" + $(this).parent().attr('class')})
  })
});
