require_relative 'parsing_utils'

module Converter
  module Testfile
    class PhraseReplacer
      def initialize(lines, label)
        @label = label
        @lines = lines
      end

      def go
        @lines = LoginReplacer.new(:login, @lines).lines
        @lines = LogoutReplacer.new(:logout, @lines).lines
        @lines = SubmitReplacer.new(:submit, @lines).lines
        @lines = AutoCompleteReplacer.new(:auto_complete, @lines).lines
        @lines = PreferredTitleLocator.new(:preferred_title, @lines).lines
        @lines = AdminMenuHoverer.new(:admin_menu, @lines).lines
        @lines = AssertConfirmation.new(:confirmation, @lines).lines
        @lines = LiteralInsteadOfTinymce.new(:literal, @lines).lines
        #        @lines = JQueryWaiter.new(:wait_jquery, @lines).lines
        @lines = TypeReplacer.new(:type, @lines).lines
        @lines = KlugeForcer.new(:kluge, @lines).lines
        @lines
      end
    end

    #
    # Work your way through the lines; loop based on @lines.size, so we will
    # adjust properly if the array expands or contracts.
    #
    # Call find_replacements_for_range_based_at_current_index,having set values
    # for @lines, @index, @first_index, @next_index, @line and @replacements.
    #
    # If a match exists based at the current index, adjust @first_index,
    # @next_index and @replacements accordingly.
    #
    # Replace the lines. Advance the index and repeat until we reach the end of
    # the lines.
    #
    class AbstractPhraseReplacer
      include ParsingUtils
      #
      def initialize(key, lines)
        @key = key
        @lines = lines
        iterate
      end

      def iterate
        index = 0
        while index < @lines.size
          @next_index = 1 + @first_index = @index = index
          @line = @lines[@index]
          @replacements = nil

          find_replacements_for_range_based_at_current_index

          if @replacements
            @lines = @lines[0...@first_index].concat(@replacements).concat(@lines[@next_index..-1])
            $reporter.replace_phrase(@key, @replacements.size)
            index += @replacements.size
          else
            index += 1
          end
        end
      end

      def advance_to_next_line
        (@next_index...@lines.size).each do |index|
          @next_index = 1 + @index = index
          @line = @lines[@index]
          return @line unless @line.comment
        end
        nil
      end

      def lines
        @lines
      end

      def comments_from_range
        @lines[@first_index...@next_index].select { |l| l.comment }
      end
    end

    #
    # Replace a login sequence with a call to vivo_login_as(email, password)
    #
    # The login sequence must start with
    #       <tr><td>clickAndWait</td><td>link=Log in</td><td></td></tr>
    # It might optionally be preceded by
    #       <tr><td>assertTitle</td><td>VIVO</td><td></td></tr>
    #    (with any title), which might be preceded by
    #       <tr><td>open</td><td>/vivo/</td><td></td></tr>
    # It must be followed by these
    #       <tr><td>type</td><td>name=loginName</td><td>testAdmin@cornell.edu</td></tr>
    #          or the field might be specified as "id=loginName"
    #       <tr><td>type</td><td>name=loginPassword</td><td>Password</td></tr>
    #          or the field might be specified as "id=loginPassword"
    #       <tr><td>clickAndWait</td><td>name=loginForm</td><td></td></tr>
    #
    # If all of these are satisfied, replace it with
    #        vivo_login_as(email, password)
    #
    class LoginReplacer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_go_to_home_page_and_login
          replace_go_to_home_page_and_login
        elsif is_simple_login
          replace_simple_login
        else
          nil
        end
      end

      def is_go_to_home_page_and_login
        is_click_on_login &&
        back_up_for_clicking_the_link &&
        back_up_for_open &&
        next_is_login_page &&
        next_is_enter_login_name &&
        next_is_enter_password &&
        next_is_submit_form
      end

      def is_simple_login
        is_click_on_login &&
        next_is_login_page &&
        next_is_enter_login_name &&
        next_is_enter_password &&
        next_is_submit_form
      end

      def is_click_on_login
        @line.match?("clickAndWait", "link=Log in")
      end

      def back_up_for_clicking_the_link
        look_for_backup("assertTitle", "VIVO")
      end

      def back_up_for_open
        look_for_backup("open", "/vivo/")
      end

      def next_is_login_page
        advance_to_next_line
        @line.match?("assertTitle", "Log in to VIVO")
      end

      def next_is_enter_login_name
        advance_to_next_line
        if m = @line.match("type", "id=loginName") || @line.match("type", "name=loginName")
          @login_name = m[2][0]
        else
          nil
        end
      end

      def next_is_enter_password
        advance_to_next_line
        if m = @line.match("type", "id=loginPassword") || @line.match("type", "name=loginPassword")
          @password = m[2][0]
        else
          nil
        end
      end

      def next_is_submit_form
        advance_to_next_line
        @line.match?("clickAndWait", "loginForm") ||
        @line.match?("clickAndWait", "name=loginForm")
      end

      def replace_go_to_home_page_and_login
        @replacements = comments_from_range
        @replacements << Line.new("vivo_login_from_home_page_as(\"%s\", \"%s\")" % [ @login_name, @password ])
      end

      def replace_simple_login
        @replacements = comments_from_range
        @replacements << Line.new("vivo_login_as(\"%s\", \"%s\")" % [ @login_name, @password ])
      end

      def look_for_backup(target1, target2 = /.*/, target3 = /.*/)
        (@first_index - 1).downto(0) do |index|
          line = @lines[index]
          if line.match?(target1, target2, target3)
            @first_index = index
            return true
          elsif line.comment
            # keep looking
          else
            return nil
          end
        end
      end
    end

    #
    # Logout is a one-for-one replacement.
    #
    # This:
    #     <tr><td>clickAndWait</td><td>link=Log out</td><td></td></tr>
    # Becomes this:
    #     vivo_logout
    #
    class LogoutReplacer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_logout_line
          figure_replacements
        else
          nil
        end
      end

      def is_logout_line
        @line.match("clickAndWait", "link=Log out")
      end

      def figure_replacements
        @replacements = [ Line.new("vivo_logout") ]
      end
    end

    #
    # Type tag:
    #    <tr><td>type</td><td>loginName</td><td>testAdmin@cornell.edu</td></tr>
    # Becomes:
    #    $browser.find_element(:name, "loginName").clear
    #    $browser.find_element(:name, "loginName").send_keys("testAdmin@cornell.edu")
    #
    # With a special case for file paths:
    #    <tr><td>type</td><td>name=rdfStream</td><td>C:\VIVO\vivo\utilities\acceptance-tests\suites\LanguageSupport\Test-utf8</td></tr>
    # Becomes:
    #    $browser.find_element(:name, "rdfStream").clear
    #    $browser.find_element(:name, "rdfStream").send_keys(tester_filepath("Test-utf8"))
    class TypeReplacer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        replace_type_file_path || replace_type
      end

      def replace_type_file_path
        @line.match("type", /.*/, /^C:(.*)$/) do |m|
          element = element_spec(m[1][0])
          value = strip_file_path(m[2][1])
          @replacements = [
            Line.new("$browser.find_element(%s).clear" % element),
            Line.new("$browser.find_element(%s).send_keys(tester_filepath(\"%s\", __FILE__))" % [ element, value ] )
          ]
        end
      end

      def replace_type
        @line.match("type") do |m|
          element = element_spec(m[1][0])
          value = value(m[2][0])
          @replacements = [
            Line.new("$browser.find_element(%s).clear" % element),
            Line.new("$browser.find_element(%s).send_keys(\"%s\")" % [ element, value ] )
          ]
        end
      end
    end

    #
    # When do we need to wait for indexing? Usually when clicking the submit on an editing
    # form.
    #
    # So, if we see
    # 1) We go to an editing form:
    #       <tr><td>assertTitle</td><td>Edit</td><td></td></tr>
    # 2) We do some stuff
    #       ...Anything that doesn't include an "assertTitle"...
    # 3) We click the "submit" button
    #       #<tr><td>clickAndWait</td><td>id=submit</td><td></td></tr>
    # 4) And it takes us to another page
    #       #<tr><td>assertTitle</td><td>...anything...</td><td></td></tr>
    # Then,
    #  1) Replace the submit button with a call to vivo_click_and_wait_for_indexing
    #
    class SubmitReplacer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_assert_title_edit &&
        encounters_submit_before_another_assert_title &&
        goes_immediately_to_new_page
          figure_replacements
        else
          nil
        end
      end

      def is_assert_title_edit
        @line.match?("assertTitle", "Edit")
      end

      def encounters_submit_before_another_assert_title
        while advance_to_next_line do
          if @line.match?("assertTitle")
            return nil
          elsif m =
          @line.match("clickAndWait", "submit") ||
          @line.match("clickAndWait", "id=submit") ||
          @line.match("clickAndWait", "css=input.submit")
            @submit_spec = element_spec(@line.field2)
            return @submit_index = @index
          end
        end
        nil
      end

      def goes_immediately_to_new_page
        advance_to_next_line
        @line.match?("assertTitle")
      end

      def figure_replacements
        @next_index = @index = @submit_index + 1
        @replacements = @lines[@first_index...@submit_index]
        @replacements << Line.new("vivo_click_and_wait_for_indexing(%s)" % [ @submit_spec ])
      end
    end

    #
    # What does it look like when we use the auto-complete feature?
    #
    # In most cases, it's
    # 1) Type zero characters into a fields
    #       <tr><td>type</td><td>id=object</td><td></td></tr>
    # 2) Send some keys to that same field
    #       <tr><td>sendKeys</td><td>id=object</td><td>Primate His</td></tr>
    # 3) Pause for 5 seconds
    #       <tr><td>pause</td><td>5000</td><td></td></tr>
    # 4) Send the KEY_DOWN key to that same field
    #       <tr><td>sendKeys</td><td>id=object</td><td>${KEY_DOWN}</td></tr>
    # 5) Click on the active menu item
    #       <tr><td>click</td><td>id=ui-active-menuitem</td><td></td></tr>
    #    or
    #       <tr><td>click</td><td>ui-active-menuitem</td><td></td></tr>
    # This should become:
    # 1) Send keys to the field
    # 2) Wait for jquery to complete
    # 3) Click on the suggested completion
    #
    class AutoCompleteReplacer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_empty_type_command &&
        next_is_send_keys_to_same_field &&
        next_is_pause &&
        next_is_key_down_to_same_field &&
        next_is_click_active_item
          figure_replacements
        else
          nil
        end
      end

      def is_empty_type_command
        @line.match("type", /.*/, "") do |m|
          @raw_element_spec = m[1][0]
        end
      end

      def next_is_send_keys_to_same_field
        advance_to_next_line
        @line.match("sendKeys", @raw_element_spec) do |m|
          @raw_text = m[2][0]
        end
      end

      def next_is_pause
        advance_to_next_line
        @line.match?("pause")
      end

      def next_is_key_down_to_same_field
        advance_to_next_line
        @line.match?("sendKeys", @raw_element_spec, "${KEY_DOWN}")
      end

      def next_is_click_active_item
        advance_to_next_line
        @line.match("click") do |m|
          # matches either form of the raw spec
          element_spec(m[1][0]) == ':id, "ui-active-menuitem"'
        end
      end

      def figure_replacements
        good_spec = element_spec(@raw_element_spec)
        good_text = value(@raw_text)

        @replacements = comments_from_range
        @replacements << Line.new("$browser.find_element(%s).send_keys(\"%s\")" % [ good_spec, good_text ])
        @replacements << Line.new("browser_wait_for_jQuery")
        @replacements << Line.new("$browser.find_element(:css, \".ui-menu-item-wrapper\").click")
      end
    end

    #
    # The old way of locating the "add preferred title" link, no longer works.
    #
    # If you find this sequence:
    #   <tr><td>clickAndWait</td><td>css=header &gt; #ARG_2000028 &gt; a.add-ARG_2000028 &gt; img.add-individual</td><td></td></tr>
    #   <tr><td>assertTitle</td><td>Edit</td><td></td></tr>
    #   <tr><td>type</td><td>id=preferredTitle</td><td>Assistant Professor</td></tr>
    # Replace the first line with this one:
    #   <tr><td>clickAndWait</td><td>css=[title="Add new preferred title entry"]</td><td></td></tr>
    # Then let the usual "clickAndWait" replacer do it's work.
    #
    class PreferredTitleLocator < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_funky_click_and_wait &&
        next_is_edit_page &&
        next_is_type_in_preferred_title
          figure_replacements
        else
          nil
        end
      end

      def is_funky_click_and_wait
        @line.match?("clickAndWait", "css=header &gt; #ARG_2000028 &gt; a.add-ARG_2000028 &gt; img.add-individual") ||
        @line.match?("clickAndWait", "css=header &gt; #ARG_2000028 &gt; a.add-ARG_2000028")
      end

      def next_is_edit_page
        advance_to_next_line
        @line.match("assertTitle", "Edit")
      end

      def next_is_type_in_preferred_title
        advance_to_next_line
        @line.match?("type", "id=preferredTitle")
      end

      def figure_replacements
        @next_index = @first_index + 1
        @replacements = [ Line.new("#<tr><td>clickAndWait</td><td>css=[title=\"Add new preferred title entry\"]</td><td></td></tr>") ]
      end
    end

    #
    # The "My account" link is not visible unless we hover over it first.
    # Same for "My profile" and "Log out"
    #
    # So, for any of these:
    #    <tr><td>verifyElementPresent</td><td>link=My account</td><td></td></tr>
    #    <tr><td>verifyElementNotPresent</td><td>link=My account</td><td></td></tr>
    #    <tr><td>clickAndWait</td><td>link=My account</td><td></td></tr>
    #    #<tr><td>verifyTextPresent</td><td>My account</td><td></td></tr>
    # Insert this line before it:
    #    $browser.action.move_to($browser.find_element(:id, "user-menu")).perform
    #
    # Same for "My profile and "Log out"
    #
    class AdminMenuHoverer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        op_matcher = /^(verifyElementPresent|verifyElementNotPresent|clickAndWait|verifyTextPresent)$/
        link_matcher = /(My profile|My account|Log out)$/
        if @line.match(op_matcher, link_matcher)
          @replacements = [
            Line.new("$browser.action.move_to($browser.find_element(:id, \"user-menu\")).perform"),
            @line
          ]
        else
          nil
        end
      end
    end

    #
    # assertConfirmation tag both checks the text of a dialog box, and confirms it.
    # The tests also (usually) include a waitForPageToLoad. We can replace that with
    # the much faster browser_wait_for_jQuery
    #
    # So,
    #    <tr><td>assertConfirmation</td><td>Are you SURE? If in doubt, CANCEL.</td><td></td></tr>
    #    <tr><td>waitForPageToLoad</td><td>5000</td><td></td></tr>
    # Becomes
    #    browser_accept_alert("Are you SURE? If in doubt, CANCEL.")
    #
    class AssertConfirmation < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_assert_confirmation &&
        optionally_has_wait_for_page_to_load
          figure_replacements
        else
          nil
        end
      end

      def is_assert_confirmation
        @line.match("assertConfirmation") do |m|
          @text = m[1][0]
        end
      end

      def optionally_has_wait_for_page_to_load
        if @lines[@index + 1].match?("waitForPageToLoad")
          @next_index += 1
        else
          true
        end
      end

      def figure_replacements
        @replacements = [ Line.new("browser_accept_alert(\"%s\")" % value(@text)) ]
      end
    end

    #
    # The application has changed so literal strings are not handled by TinyMCE.
    # We have a list of fields for which this is true.
    #
    # So, if we click on a link in our list, and it leads to the Edit page, and
    # we enter text into TinyMCE, then:
    #    <tr><td>clickAndWait</td><td>//h3[@id='freetextKeyword']/a/img</td><td></td></tr>
    #    <tr><td>assertTitle</td><td>Edit</td><td></td></tr>
    #    <tr><td>waitForElementPresent</td><td>tinymce</td><td></td></tr>
    #    <tr><td>verifyTextPresent</td><td>Some text</td><td></td></tr>
    #    <tr><td>runScript</td><td>tinyMCE.activeEditor.setContent('Gorillas')</td><td></td>
    # Becomes:
    #    <tr><td>clickAndWait</td><td>//h3[@id='freetextKeyword']/a/img</td><td></td></tr>
    #    <tr><td>assertTitle</td><td>Edit</td><td></td></tr>
    #    <tr><td>verifyTextPresent</td><td>Some text</td><td></td></tr>
    #    <tr><td>type</td><td>literal</td><td>Gorillas</td></tr>
    #
    # Note: different field specs in the "clickAndWait" result in different
    # field names in the "type".
    #
    # Note: both "verifyTextPresent" and "waitForElementPresent" are optional.
    # If "waitForElementPresent/tinymce" is found, it should be removed.
    # If "verifyTextPresent" is found, it should remain.
    #
    class LiteralInsteadOfTinymce < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_click_on_a_recognized_field &&
        next_is_edit_page &&
        advance_past_optional_lines &&
        next_is_enter_to_tinymce
          figure_replacements
        else
          nil
        end
      end

      def is_click_on_a_recognized_field
        field_specs = {
          "//h3[@id='freetextKeyword']/a/img" => "literal",
          "//h3[@id='abbreviation']/a/img" => "literal",
          "//h3[@id='researcherId']/a/img" => "literal",
          "//h3[@id='scopusId']/a/img" => "literal",
          "css=a.add-researcherId &gt; img.add-individual" => "literal",
          "css=a.add-ARG_2000028 &gt; img.add-individual" => "emailAddress",
          "css=a.add-ARG_0000197 &gt; img.add-individual" => "literal",
          "css=a.add-eRACommonsId &gt; img.add-individual" => "literal",
          "css=a.edit-freetextKeyword > img.edit-individual" => "literal",
          "css=a.edit-abbreviation > img.edit-individual" => "literal",
          "css=a.edit-researcherId > img.edit-individual" => "literal",
          "css=a.edit-scopusId > img.edit-individual" => "literal",
          "css=a.edit-researcherId &gt; img.edit-individual" => "literal",
          "css=a.edit-ARG_2000028 &gt; img.edit-individual" => "emailAddress",
          "css=a.edit-ARG_0000197 &gt; img.edit-individual" => "literal",
          "css=a.edit-eRACommonsId &gt; img.edit-individual" => "literal",
          "xpath=//h3[@id='oclcnum']/a/img" => "literal",
          "//h3[@id='architecturalDetails']/a/img" => "literal"
          
        }
        if [ "click", "clickAndWait"].include?(@line.field1)
          @field_name = field_specs[@line.field2]
        end
      end

      def next_is_edit_page
        advance_to_next_line
        @line.match?("assertTitle", "Edit")
      end

      def advance_past_optional_lines
        (@next_index...@lines.size).each do |index|
          @next_index = 1 + @index = index
          @line = @lines[@index]
          return @line unless @line.comment || @line.match?("verifyTextPresent") || @line.match?("waitForElementPresent", "tinymce")
        end
        nil
      end

      def next_is_enter_to_tinymce
        @line.match("runScript", /^tinyMCE.activeEditor.setContent\('(.*)'\)$/) do |m|
          @content = m[1][1]
        end
      end

      def figure_replacements
        puts ">>>>next_is_replacements"
        @replacements = @lines[@first_index...(@next_index - 1)].reject { |line| line.match?("waitForElementPresent", "tinymce")}
        @replacements << Line.new("<tr><td>type</td><td>%s</td><td>%s</td></tr>" % [ @field_name, @content ])
      end
    end

    #
    # When we arrive on the Home page, we need to wait for the AJAX calls before
    # we can see the entire page. This is true for some other pages as well.
    #
    # There are many ways of reaching pages. We can open a page, login, logout,
    # click the home tab, etc. However, Selenium IDE was kind enough to insert
    # an "assertTitle" tag after each one of them.
    #
    # This is probably overkill, but as with most overkill, it should be effective.
    #
    # This is a simple case of finding a line that meets the critria and adding
    # a line after it.
    #
    class JQueryWaiter < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        if is_assert_title
          insert_wait
        else
          nil
        end
      end

      def is_assert_title
        @line.match?("assertTitle")
      end

      def insert_wait
        @replacements = [@line, Line.new("browser_wait_for_jQuery")]
      end

    end

    #
    # FORCE THESE CHANGES
    #
    class KlugeForcer < AbstractPhraseReplacer
      def find_replacements_for_range_based_at_current_index
        do_force_comment ||
        do_force_insert
      end

      def do_force_comment
        @line.text.match(/^#<!-- FORCE COMMENT (.*) -->$/) do |m|
          @next_index += 1
          @replacements = [
            Line.new("#>>>  " + m[1]),
            Line.new("#>>>  " + @lines[@index + 1].text)
          ]
        end
      end

      def do_force_insert
        @line.text.match(/^#<!-- FORCE INSERT (.*) -->$/) do |m|
          @replacements = [Line.new(m[1])]
        end
      end

    end

  end
end
