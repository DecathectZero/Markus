require 'spec_helper'

describe SectionsController do

  context 'A logged in Student' do
    before do
      @student = Student.create(user_name: 'jdoe',
                                last_name: 'doe',
                                first_name: 'john')
    end

    it 'on index' do
      get_as @student, :index
      expect(response.status).to eq(404)
    end

    it 'on create new section' do
      post_as @student, :create
      expect(response.status).to eq(404)
    end

    it 'on edit section' do
      post_as @student, :edit, id: Section.create!(name: 'test').id
      expect(response.status).to eq(404)
    end

    it 'on update new section' do
      post_as @student, :update, id: Section.create!(name: 'test').id
      expect(response.status).to eq(404)
    end

    it 'not be able to delete a section' do
      section = Section.create!(name: 'test')
      delete_as @student, :destroy, id: section
      expect(response.status).to eq(404)
      expect(Section.find(section.id)).to be_truthy
    end
  end

  context 'A logged in Admin' do
    before do
      @admin = Admin.create(user_name: 'adoe',
                            last_name: 'doe',
                            first_name: 'adam')
    end

    it 'on index' do
      get_as @admin, :index
      expect(response.status).to eq(200)
    end

    it 'on create new section' do
      post_as @admin, :create, {section: {name: 'section_01'}}

      expect(response).to be_redirect
      expect(flash[:success]).to eq([I18n.t('sections.create.success', name: 'section_01')])
      expect(Section.find_by_name('section_01')).to be_truthy
    end

    it 'not be able to create a section with the same name as a existing one' do
      section = Section.create(name: 'section_01')
      post_as @admin, :create, {section: {name: section.name}}
      expect(response.status).to eq(200)
      expect(flash[:error]).to eq([I18n.t('sections.create.error')])
    end

    it 'not be able to create a section with a blank name' do
      post_as @admin, :create, {section: {name: ''}}
      expect(Section.find_by_name('')).to be_nil
      expect(response.status).to eq(200)
      expect(flash[:error]).to eq([I18n.t('sections.create.error')])
    end

    it 'on edit section' do
      post_as @admin, :edit, id: Section.create!(name: 'test').id
      expect(response.status).to eq(200)
    end

    it 'be able to update a section name to "no section"' do
      section = Section.create(name: 'section_01')
      put_as @admin,
             :update,
             id: section.id,
             section: {name: 'no section'}

      expect(response).to be_redirect
      expect(flash[:success]).to eq([I18n.t('sections.update.success', name: 'no section')])
      expect(Section.find_by_name('no section')).to be_truthy
    end

    it 'not see a table if no students in this section' do
      section = Section.create(name: 'section_01')
      get_as @admin, :edit, id: section.id
      expect(response.body.to_s.match('section_students')).to be_nil
    end

    it 'not be able to edit a section name to an existing name' do
      section = Section.create(name: 'section_01')
      section2 = Section.create(name: 'section_02')
      put_as @admin,
             :update,
             id: section.id,
             section: {name: section2.name}
      expect(response.status).to eq(200)
      expect(flash[:error]).to eq([I18n.t('sections.update.error')])
    end

    context 'with an already created section' do
      before :each do
        @section = Section.create(name: 'section_01')
      end

      it 'be able to delete a section' do
        delete_as @admin, :destroy, id: @section.id
        expect(flash[:success]).to eq([I18n.t('sections.destroy.success')])
      end

      it 'not be able to delete a section with students in it' do
        student = Student.create(user_name: 'jdoe',
                                  last_name: 'doe',
                                  first_name: 'john')
        @section.students << student
        delete_as @admin, :destroy, id: @section.id
        expect(flash[:error]).to eq([I18n.t('sections.destroy.not_empty')])
        expect(Section.find(@section.id)).to be_truthy
      end
    end
  end
end
