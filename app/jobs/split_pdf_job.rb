class SplitPDFJob < ActiveJob::Base
  include ActiveJob::Status

  queue_as MarkusConfigurator.markus_job_split_pdf_queue_name

  def perform(exam_template, path)
    m_logger = MarkusLogger.instance
    begin
      progress.total = 0
      # Create directory for files whose QR code couldn't be parsed
      error_dir = File.join(exam_template.base_path, 'error')
      raw_dir = File.join(exam_template.base_path, 'raw')
      FileUtils.mkdir error_dir unless Dir.exists? error_dir
      FileUtils.mkdir raw_dir unless Dir.exists? raw_dir

      basename = File.basename path, '.pdf'
      pdf = CombinePDF.load path
      partial_exams = Hash.new do |hash, key|
        hash[key] = []
      end
      pdf.pages.each_index do |i|
        page = pdf.pages[i]
        new_page = CombinePDF.new
        new_page << page
        new_page.save File.join(raw_dir, "#{basename}-#{i}.pdf")

        # Snip out the part of the PDF that contains the QR code.
        img = Magick::Image::read(File.join(raw_dir, "#{basename}-#{i}.pdf")).first
        qr_img = img.crop 0, 10, img.columns, img.rows / 5
        qr_img.write File.join(raw_dir, "#{basename}-#{i}.png")

        # qrcode_string = ZXing.decode new_page.to_pdf
        qrcode_string = ZXing.decode qr_img.to_blob
        qrcode_regex = /(?<short_id>\w+)-(?<exam_num>\d+)-(?<page_num>\d+)/
        m = qrcode_regex.match qrcode_string
        if m.nil?
          new_page.save File.join(error_dir, "#{basename}-#{i}.pdf")
        else
          partial_exams[m[:exam_num]] << [m[:page_num].to_i, page]
          m_logger.log("#{m[:short_id]}: exam number #{m[:exam_num]}, page #{m[:page_num]}")
        end
      end

      save_pages(exam_template, partial_exams)
      progress.increment
    end
     m_logger.log('Split pdf process done')
    rescue => e
      Rails.logger.error e.message
      raise e
  end

  # Save the pages into groups for this assignment
  def save_pages(exam_template, partial_exams)
    complete_dir = File.join(exam_template.base_path, 'complete')
    incomplete_dir = File.join(exam_template.base_path, 'incomplete')

    groupings = []
    partial_exams.each do |exam_num, pages|
      next if pages.empty?
      pages.sort_by! { |page_num, _| page_num }

      # Save raw pages
      if pages.length == exam_template.num_pages
        destination = File.join complete_dir, "#{exam_num}"
      else
        destination = File.join incomplete_dir, "#{exam_num}"
      end
      FileUtils.mkdir_p destination unless Dir.exists? destination
      pages.each do |page_num, page|
        new_pdf = CombinePDF.new
        new_pdf << page
        new_pdf.save File.join(destination, "#{page_num}.pdf")
      end

      group = Group.find_or_create_by(
        group_name: group_name_for(exam_template, exam_num),
        repo_name: group_name_for(exam_template, exam_num)
      )

      groupings << Grouping.find_or_create_by(
        group: group,
        assignment: exam_template.assignment
      )

      group.access_repo do |repo|
        assignment_folder = exam_template.assignment.repository_folder
        txn = repo.get_transaction(Admin.first.user_name)


        # Pages that belong to a division
        exam_template.template_divisions.each do |division|
          new_pdf = CombinePDF.new
          pages.each do |page_num, page|
            if division.start <= page_num && page_num <= division.end
              new_pdf << page
            end
          end
          txn.add(File.join(assignment_folder,
                            "#{division.label}.pdf"),
                  new_pdf.to_pdf,
                  'application/pdf'
          )
        end

        # Pages that don't belong to any division
        extra_pages = pages.reject do |page_num, _|
          exam_template.template_divisions.any? do |division|
            division.start <= page_num && page_num <= division.end
          end
        end
        extra_pages.sort_by! { |page_num, _| page_num }
        extra_pdf = CombinePDF.new
        cover_pdf = CombinePDF.new
        start_page = 0
        if extra_pages[0][0] == 1
          cover_pdf << extra_pages[0][1]
          start_page = 1
        end
        extra_pdf << extra_pages[start_page..extra_pages.size].collect { |_, page| page }
        txn.add(File.join(assignment_folder,
                          "EXTRA.pdf"),
                extra_pdf.to_pdf,
                'application/pdf'
        )
        txn.add(File.join(assignment_folder,
                          "COVER.pdf"),
                cover_pdf.to_pdf,
                'application/pdf'
        )
        repo.commit(txn)
      end
    end
    SubmissionsJob.perform_later(groupings)
  end

  def group_name_for(exam_template, exam_num)
    "#{exam_template.assignment.short_identifier}_paper_#{exam_num}"
  end
end
