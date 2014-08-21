$(document).ready ->
  $.extend($.fn.dataTable.defaults, {
    dom: "<'row'<'col-md-6'l><'col-md-6'f>r>t<'row'<'col-md-6'i><'col-md-6'p>>",
    pagingType: "bootstrap",
    pageLength: 50
  })

  $('.datatable').dataTable()

  tableNeedsPagination = $('.datatable-sorted tbody tr').length > 10

  discoverSortOrder = ->
    tableSortPreferences = $('.datatable-sorted th').map (ix, element) ->
      defaultSortDirection = $(element).data('default-sort')
      if defaultSortDirection then [[ix, defaultSortDirection]] else null
    tableSortPreferences[0]

  $('.datatable-sorted').dataTable
    paging: tableNeedsPagination,
    order: discoverSortOrder() || [[ 1, "desc" ]],
    columnDefs: [
      {targets: ['date'], type: "date"}
    ]

  $('.datatable-checkins').dataTable
    paging: false,
    order: [[ 0, "asc" ]],
    columnDefs: [
      {targets: ['checkins-action'], sortable: false}
    ]