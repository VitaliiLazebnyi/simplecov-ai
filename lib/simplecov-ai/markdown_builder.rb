# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Responsible for compiling static text representations from evaluated coverage metrics,
      # optimizing layout size, orchestrating string IO buffers, and halting upon token exhaustion.
      # Serves as the primary mutation boundary to format AI consumption targets.
      class MarkdownBuilder
        extend T::Sig
        # Groups unexecuted lines and branches under their common semantic node.
        class DeficitGroup < T::Struct
          # @return [ASTResolver::SemanticNode, nil] The corresponding structural boundary
          prop :semantic_node, T.nilable(ASTResolver::SemanticNode), default: nil
          # @return [Array<SimpleCov::SourceFile::Line>] The missed source lines
          prop :lines, T::Array[SimpleCov::SourceFile::Line], default: []
          # @return [Array<SimpleCov::SourceFile::Branch>] The missed conditional branches
          prop :branches, T::Array[SimpleCov::SourceFile::Branch], default: []
        end

        # Initializes the Markdown sequence compilation.
        #
        # @param result [SimpleCov::Result] Application-wide coverage aggregation metrics
        # @param config [Configuration] Pre-registered runtime toggles
        sig { params(result: SimpleCov::Result, config: Configuration).void }
        def initialize(result, config)
          @result = T.let(result, SimpleCov::Result)
          @config = T.let(config, Configuration)
          @buffer = T.let(StringIO.new, StringIO)
          @file_count = T.let(0, Integer)
          @truncated = T.let(false, T::Boolean)
          @ast_cache = T.let({}, T::Hash[String, T::Array[ASTResolver::SemanticNode]])
        end

        # Executes the primary buffer composition logic yielding a monolithic compiled output.
        # Deficits are intrinsically sorted to surface the most crucial test gaps immediately.
        #
        # @return [String] Synthesized string digest of resolved target files and metrics
        sig { returns(String) }
        def build
          write_header
          write_deficits
          write_bypasses if @config.include_bypasses
          write_truncation_warning if @truncated
          @buffer.string
        end

        private

        # Writes the summary header containing global coverage percentages and generation metadata.
        sig { void }
        def write_header
          status = @result.covered_percent >= 100.0 ? 'PASSED' : 'FAILED'
          time_str = Time.now.to_s # UI timezone requirement

          @buffer.puts '# AI Coverage Digest'
          @buffer.puts "**Status:** #{status}"
          @buffer.puts "**Global Line Coverage:** #{@result.covered_percent.round(1)}%"

          branch_pct = begin
            T.cast(@result.covered_branches, Float) / @result.total_branches * 100
          rescue StandardError
            0.0
          end
          @buffer.puts "**Global Branch Coverage:** #{branch_pct.round(1)}%"
          @buffer.puts "**Generated At:** #{time_str}"
          @buffer.puts ''
        end

        # Iterates through files with coverage deficits and coordinates their AST parsing and snippet generation.
        sig { void }
        def write_deficits
          files_enum = @result.files
          files_array = T.let(files_enum.to_a, T::Array[SimpleCov::SourceFile])
          # SCMD-REQ-014: Sort by coverage percent ASC, then by filename
          files = T.let(
            files_array.reject { |f| f.covered_percent >= 100.0 }
             .sort_by { |f| [f.covered_percent, f.filename] },
            T::Array[SimpleCov::SourceFile]
          )

          return if files.empty?

          @buffer.puts "## Coverage Deficits\n\n"

          files.each do |file|
            # Check size limits SCMD-REQ-012
            if @buffer.size / 1024.0 > @config.max_file_size_kb
              @truncated = true
              break
            end

            @buffer.puts "### `#{file.project_filename}`"

            begin
              nodes = resolve_ast(file.filename)
            rescue StandardError => e
              @buffer.puts "- **ERROR:** AST Parsing Failed (`#{e.class}`)"
              next
            end

            process_deficits(file, nodes)
          end
        end

        # Groups deficit lines and branches by their corresponding AST semantic nodes and delegates formatting.
        #
        # @param file [SimpleCov::SourceFile] The file being processed.
        # @param nodes [Array<ASTResolver::SemanticNode>] The resolved semantic nodes for the file.
        sig { params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode]).void }
        def process_deficits(file, nodes)
          node_deficits = T.let({}, T::Hash[String, DeficitGroup])

          file.missed_lines.each do |line|
            line_num = line.line_number
            node = nodes.find { |n| line_num >= n.start_line && line_num <= n.end_line }
            node_name = node ? node.name : "Line #{line_num}"
            node_deficits[node_name] ||= DeficitGroup.new(semantic_node: node)
            T.must(node_deficits[node_name]).lines << line
          end

          if file.respond_to?(:branches)
            branches = file.branches
            if branches.any?
              file.missed_branches.each do |branch|
                start_line = branch.start_line
                end_line = branch.end_line
                node = nodes.find { |n| start_line >= n.start_line && end_line <= n.end_line }
                node_name = node ? node.name : "Lines #{start_line}-#{end_line}"
                node_deficits[node_name] ||= DeficitGroup.new(semantic_node: node)
                T.must(node_deficits[node_name]).branches << branch
              end
            end
          end

          source_lines = T.let(nil, T.nilable(T::Array[String]))

          node_deficits.each do |node_name, group|
            if @buffer.size / 1024.0 > @config.max_file_size_kb
              @truncated = true
              break
            end

            @buffer.puts "- `#{node_name}`"

            if @config.granularity == :coarse
              @buffer.puts '  - **Deficit:** Contains unexecuted lines or branches.'
              next
            end

            source_lines ||= begin
              File.readlines(file.filename)
            rescue StandardError
              []
            end

            node = group.semantic_node
            lines = group.lines
            branches = group.branches

            lines.each do |line|
              write_line_snippet(line, source_lines, node)
            end

            branches.each do |branch|
              write_branch_snippet(branch, source_lines, node)
            end
          end

          @buffer.puts ''
        end

        # Formats and appends a single line deficit snippet to the markdown buffer.
        #
        # @param line [SimpleCov::SourceFile::Line] The unexecuted source line.
        # @param source_lines [Array<String>] The raw text lines of the file.
        # @param node [ASTResolver::SemanticNode, nil] The semantic node enclosing the deficit.
        sig do
          params(line: SimpleCov::SourceFile::Line, source_lines: T::Array[String],
                 node: T.nilable(ASTResolver::SemanticNode)).void
        end
        def write_line_snippet(line, source_lines, node)
          line_num = line.line_number
          text = fetch_snippet_text([line_num], source_lines)
          occurrence_str = calculate_occurrence(line_num, source_lines, node)
          @buffer.puts "  - **Line Deficit:** #{occurrence_str}`#{truncate_snippet(text)}`"
        end

        # Formats and appends a branch conditional deficit snippet to the markdown buffer.
        #
        # @param branch [SimpleCov::SourceFile::Branch] The unexecuted conditional branch.
        # @param source_lines [Array<String>] The raw text lines of the file.
        # @param node [ASTResolver::SemanticNode, nil] The semantic node enclosing the deficit.
        sig do
          params(branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String],
                 node: T.nilable(ASTResolver::SemanticNode)).void
        end
        def write_branch_snippet(branch, source_lines, node)
          start_line = branch.start_line
          end_line = branch.end_line
          lines_range = T.cast((start_line..end_line).to_a, T::Array[Integer])
          text = fetch_snippet_text(lines_range, source_lines)
          occurrence_str = calculate_occurrence(start_line, source_lines, node)
          @buffer.puts "  - **Branch Deficit:** Missing coverage for conditional `#{truncate_snippet(text)}` #{occurrence_str}".rstrip
        end

        # Extracts and normalizes exact string literals from the source file arrays.
        #
        # @param line_nums [Array<Integer>] Target line coordinates.
        # @param source_lines [Array<String>] The raw text lines of the file.
        # @return [String] Joined snippet text.
        sig { params(line_nums: T::Array[Integer], source_lines: T::Array[String]).returns(String) }
        def fetch_snippet_text(line_nums, source_lines)
          line_nums.filter_map { |ln| source_lines[ln - 1]&.strip }.reject(&:empty?).join(' ')
        end

        # Disambiguates identical code snippets within the same semantic block (e.g., "(Occurrence 2 of 3)").
        #
        # @param line_num [Integer] The target coordinate of the deficit.
        # @param source_lines [Array<String>] Raw file contents.
        # @param node [ASTResolver::SemanticNode, nil] The semantic node boundary to search within.
        # @return [String] Occurrence label or empty string if unique.
        sig do
          params(line_num: Integer, source_lines: T::Array[String],
                 node: T.nilable(ASTResolver::SemanticNode)).returns(String)
        end
        def calculate_occurrence(line_num, source_lines, node)
          return '' if node.nil?

          first_line_of_snippet = source_lines[line_num - 1]&.strip
          return '' if first_line_of_snippet.nil? || first_line_of_snippet.empty?

          occurrences = 0
          current_occurrence = 1

          (node.start_line..node.end_line).each do |ln|
            line_content = source_lines[ln - 1]&.strip
            next unless line_content

            if line_content == first_line_of_snippet
              occurrences += 1
              current_occurrence = occurrences if ln == line_num
            end
          end

          occurrences > 1 ? "(Occurrence #{current_occurrence} of #{occurrences}) " : ''
        end

        # Safely limits the character length of a code snippet according to global configurations.
        #
        # @param text [String] The snippet to potentially truncate.
        # @return [String] Truncated string with trailing ellipses if limit exceeded.
        sig { params(text: String).returns(String) }
        def truncate_snippet(text)
          max_chars = @config.max_snippet_lines * 80
          text.length > max_chars ? "#{text[0...max_chars]}..." : text
        end

        # Caches and retrieves AST resolutions to eliminate redundant filesystem I/O operations.
        #
        # @param filename [String] The absolute path to parse.
        # @return [Array<ASTResolver::SemanticNode>] Parsed AST semantic blocks.
        sig { params(filename: String).returns(T::Array[ASTResolver::SemanticNode]) }
        def resolve_ast(filename)
          @ast_cache[filename] ||= ASTResolver.resolve(filename)
        end

        # Scans resolved AST blocks to report explicitly defined coverage ignores (e.g., :nocov:).
        sig { void }
        def write_bypasses
          has_bypasses = T.let(false, T::Boolean)
          bypass_buffer = T.let(StringIO.new, StringIO)

          files_enum = @result.files
          files_array = T.let(files_enum.to_a, T::Array[SimpleCov::SourceFile])

          files_array.each do |file|
            begin
              nodes = resolve_ast(file.filename)
            rescue StandardError
              next
            end

            nodes_with_bypasses = nodes.select { |n| n.bypasses.any? }
            next if nodes_with_bypasses.empty?

            has_bypasses = true
            write_file_bypasses(bypass_buffer, file, nodes_with_bypasses)
          end

          return unless has_bypasses

          @buffer.puts "## Ignored Coverage Bypasses\n\n"
          @buffer.puts bypass_buffer.string
        end

        # Formats the Markdown layout for files explicitly bypassing test coverage.
        #
        # @param buffer [StringIO] The temporary buffer isolating bypass text.
        # @param file [SimpleCov::SourceFile] The file containing bypasses.
        # @param bypasses [Array<ASTResolver::SemanticNode>] AST nodes decorated with bypass comments.
        sig do
          params(buffer: StringIO, file: SimpleCov::SourceFile, bypasses: T::Array[ASTResolver::SemanticNode]).void
        end
        def write_file_bypasses(buffer, file, bypasses)
          buffer.puts "### `#{file.project_filename}`"
          bypasses.each do |node|
            buffer.puts "- `#{node.name}`\n  - **Bypass Present:** Contains `:nocov:` directive artificially ignoring coverage."
          end
          buffer.puts ''
        end

        # Appends a critical alert if the output hit the token-ceiling constraint and was forcibly terminated.
        sig { void }
        def write_truncation_warning
          @buffer.puts '> **[WARNING] TRUNCATION NOTIFICATION:**'
          @buffer.puts "> The total coverage deficit report exceeded the maximum token constraint (#{@config.max_file_size_kb} kB). The report was truncated. The deficits detailed above represent the lowest-coverage (most critical) files. Please resolve these deficits to reveal the remaining uncovered files in subsequent test runs."
        end
      end
    end
  end
end
