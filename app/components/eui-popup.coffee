`import styleSupport from 'appkit/mixins/style-support'`
`import popupLayout from 'appkit/templates/components/eui-popup'`

popup = Em.Component.extend styleSupport,
  layout: popupLayout
  classNames: ['eui-popup']
  classNameBindings: ['isOpen::eui-closing']
  attributeBindings: ['tabindex']

  labelPath: 'label'
  options: null
  listHeight: '80'
  listRowHeight: '20'
  searchString: null

  selection: null # Option currently selected
  highlightedIndex: -1 # Option currently highlighted
  action: undefined # Controls what happens if option is clicked. Select it or perform Action

  previousFocus: null # Where the user's focus was before the popup was opened (only for keyboard nav)

  hide: ->
    @set('isOpen', false).set('highlightedIndex', -1)
    $(window).unbind('scroll.emberui')
    $(window).unbind('click.emberui')
    @get('previousFocus').focus()

    @$().one 'webkitAnimationEnd oanimationend msAnimationEnd animationend', =>
      @destroy()

  didInsertElement: ->
    @set('isOpen', true)
    @set('previousFocus', $("*:focus"))
    Ember.run.next this, -> @focusOnSearch()

  focusOnSearch: ->
    @$().find('input:first').focus()

  filteredOptions: (->
    options = @get('options')
    query = @get('searchString')

    return [] unless options
    return options unless query

    labelPath = @get('labelPath')

    escapedQuery = query.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&")
    regex = new RegExp(escapedQuery, 'i')

    filteredOptions = options.filter (item, index, self) ->
      return if item == null

      label = item.get?(labelPath) or item[labelPath]
      regex.test(label)

    return filteredOptions
  ).property 'options.@each', 'labelPath', 'searchString'

  hasNoOptions: Ember.computed.empty 'filteredOptions'

  optionsLengthDidChange: (->
    @updateListHeight()
  ).observes 'filteredOptions.length'

  updateListHeight: ->
    optionCount = @get('filteredOptions.length')
    rowHeight = @get('listRowHeight')

    if optionCount <= 12
      @set('listHeight', (optionCount * rowHeight))
    else
      @set('listHeight', (10 * rowHeight))


  # Keyboard controls

  KEY_MAP:
    27: 'escapePressed'
    13: 'enterPressed'
    38: 'upArrowPressed'
    40: 'downArrowPressed'

  keyDown: (event) ->
    keyMap = @get 'KEY_MAP'
    method = keyMap[event.which]
    @get(method)?.apply(this, arguments) if method

  escapePressed: (event) ->
    @hide()

  enterPressed: (event) ->
    event.preventDefault()
    event = @get('event')
    selection = @get('options')[@get('highlighted')]

    if event == 'select'
      @set('selection', selection)

    else if event == 'action'
      action = selection.get('action')
      @get('targetObject').triggerAction({action})

    @hide()

  downArrowPressed: (event) ->
    event.preventDefault() # Don't let the page scroll down
    @adjustHighlight(1)

  upArrowPressed: (event) ->
    event.preventDefault() # Don't let the page scroll down
    @adjustHighlight(-1)


  adjustHighlight: (indexAdjustment) ->
    highlightedIndex = @get('highlightedIndex')
    options = @get('filteredOptions')
    optionsLength = options.get('length')
    newIndex


    # If the current index is out of bounds they searched
    # so we adjust it back in
    if highlightedIndex >= optionsLength
      newIndex = 0 if indexAdjustment == 1

    else
      newIndex = highlightedIndex + indexAdjustment

      # Don't let highlighted option get out of bounds
      if newIndex >= optionsLength
        newIndex = optionsLength - 1

      else if newIndex < 0
        newIndex = 0

    return @set('highlightedIndex', newIndex)


  # List View

  listView: Ember.ListView.extend
    css:
      position: 'relative'
      overflow: 'auto'
      '-webkit-overflow-scrolling': 'touch'
      'overflow-scrolling': 'touch'

    classNames: ['eui-options']
    height: Ember.computed.alias 'controller.listHeight'
    rowHeight: Ember.computed.alias 'controller.listRowHeight'

    didInsertElement: ->
      @_super()

      # Prevents mouse scroll events from passing through to the div
      # behind the popup when listView is scrolled to the end. Fixes
      # the popup closing if you scroll too far down
      @.$().bind('mousewheel DOMMouseScroll', (e) =>
        e.preventDefault()
        scrollTo = @get('scrollTop')

        if e.type == 'mousewheel'
          scrollTo += (e.originalEvent.wheelDelta * -1)

        else if e.type == 'DOMMouseScroll'
          scrollTo += 40 * e.originalEvent.detail

        @scrollTo(scrollTo)
      )

    itemViewClass: Ember.ListItemView.extend
      classNames: ['eui-option']
      classNameBindings: ['isHighlighted:eui-hover', 'isSelected:eui-selected']
      template: Ember.Handlebars.compile('{{view.label}}')

      labelPath: Ember.computed.alias 'controller.labelPath'

      # creates Label property based on specified labelPath
      labelPathDidChange: (->
        labelPath = @get 'labelPath'
        Ember.defineProperty(this, 'label', Ember.computed.alias("content.#{labelPath}"))
        @notifyPropertyChange 'label'
      ).observes 'content', 'labelPath'

      initializeLabelPath: (->
        @labelPathDidChange()
      ).on 'init'

      # TODO: Unsure why this is not done automatically. Without this @get('content') returns undefined.
      updateContext: (context) ->
        @_super context
        @set 'content', context

      isHighlighted: Ember.computed ->
        options = @get('controller.filteredOptions')
        index = @get('controller.highlightedIndex')
        option = options[index]

        option is @get('content')
      .property 'controller.highlightedIndex', 'content'

      isSelected: Ember.computed ->
        @get('controller.selection') is @get('content')
      .property 'controller.selection', 'content'

      click: ->
        option = @get('content')
        event = @get('controller.event')

        if event == 'select'
          @set('controller.selection', option)

        else if event == 'action'
          action = option.get('action')
          @get('controller.targetObject').triggerAction({action})

        @get('controller').hide()

      mouseEnter: ->
        options = @get('controller.filteredOptions')
        hoveredOption = @get('content')

        for option, index in options
          if option == hoveredOption
            @set 'controller.highlightedIndex', index
            break


popup.reopenClass
  show: (options = {}) ->
    popup = @.create options
    popup.container = popup.get('targetObject.container')
    popup.appendTo '.ember-application'

    popup.updateListHeight()

    Ember.run.next this, -> @position(options.targetObject, popup)
    popup

  position: (targetObject, popup) ->
    element = targetObject.$()
    popupElement = popup.$()

    offset = element.offset()

    # set a reasonable min-width on the popup before we caclulate its actual size
    elementWidthMinusPopupPadding = element.width() - parseFloat(popupElement.css('paddingLeft')) - parseFloat(popupElement.css('paddingRight'))
    popupElement.css('min-width', elementWidthMinusPopupPadding)

    # calculate all the numbers needed to set positioning
    elementPositionTop = offset.top - element.scrollTop()
    elementPositionLeft = offset.left - element.scrollLeft()
    elementHeight = element.height()
    elementWidth = element.width()
    popupWidth = popupElement.width()
    popupHorizontalPadding = parseFloat(popupElement.css('paddingLeft')) + parseFloat(popupElement.css('paddingRight'))
    windowScrollTop = $(window).scrollTop()
    windowScrollLeft = $(window).scrollLeft()

    popupPositionTop = elementPositionTop + elementHeight  - windowScrollTop
    popupPositionLeft = elementPositionLeft + elementWidth - popupWidth - popupHorizontalPadding - windowScrollLeft

    popupElement.css('top', popupPositionTop)
    popupElement.css('left', popupPositionLeft)

    $(window).bind 'scroll.emberui', ->
      popup.hide()

    $(window).bind 'click.emberui', (event) ->
      unless $(event.target).parents('.eui-popup').length
        event.preventDefault()
        popup.hide()


`export default popup`
