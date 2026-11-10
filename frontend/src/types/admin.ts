import type {School} from './portal';
export type AdminTab='overview'|'students'|'events'|'stories'|'schools'|'reports'|'settings';
export type AdminSummary={totalStudents:number;totalSchools:number;completed:number;points:number;updatedAt:string};
export type AdminStudent={id:string;name:string;age:number|null;school:string|null;schoolId:string|null;className:string;createdAt:string;status:string;completed:number;points:number;birthDate?:string|null;guardian?:string|null};
export type AdminStudentsData={students:AdminStudent[];total:number;page:number;pageSize:number;schools:School[];updatedAt:string};
export type AdminStudentDetail={student:AdminStudent;journeys:{id:string;cycle:number;status:string;createdAt:string;completedAt:string|null;completed:number;points:number}[];attempts:{id:string;title:string;level:string;cycle:number|null;status:string;stage:string;answered:number;totalQuestions:number;includedInTotals:boolean;points:number|null;completedAt:string|null}[];updatedAt:string};
