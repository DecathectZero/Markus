class SubmissionsJob < ActiveJob::Base
  include ActiveJob::Status

  queue_as MarkusConfigurator.markus_job_collect_submissions_queue_name

  def perform(groupings, options = {})
    return if groupings.empty?

    m_logger = MarkusLogger.instance
    assignment = groupings.first.assignment

    begin
      progress.total = groupings.size
      groupings.each do |grouping|
        m_logger.log("Now collecting: #{assignment.short_identifier} for grouping: " +
                     "#{grouping.id}")
        if options[:revision_number].nil?
          time = assignment.submission_rule.calculate_collection_time.localtime
          new_submission = Submission.create_by_timestamp(grouping, time)
        else
          new_submission = Submission.create_by_revision_number(grouping, options[:revision_number])
        end

        if assignment.submission_rule.is_a? GracePeriodSubmissionRule
          # Return any grace credits previously deducted for this grouping.
          assignment.submission_rule.remove_deductions(grouping)
        end

        if options[:apply_late_penalty].nil? || options[:apply_late_penalty]
          new_submission = assignment.submission_rule.apply_submission_rule(
            new_submission)
        end

        unless grouping.error_collecting
          grouping.is_collected = true
        end

        grouping.save
        progress.increment
      end
      m_logger.log('Submission collection process done')
    rescue => e
      Rails.logger.error e.message
      raise e
    end
  end
end
